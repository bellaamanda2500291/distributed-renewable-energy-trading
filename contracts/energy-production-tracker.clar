;; Distributed Renewable Energy Trading Platform - Energy Production Tracker
;; Tracks and verifies renewable energy generation from prosumers

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-insufficient-energy (err u104))
(define-constant err-unauthorized (err u105))

;; Data Variables
(define-data-var total-registered-producers uint u0)
(define-data-var total-energy-produced uint u0)
(define-data-var total-verified-production uint u0)

;; Data Maps
(define-map producers
  { producer: principal }
  {
    producer-id: (buff 32),
    energy-type: (string-ascii 16),
    capacity: uint,
    location: { latitude: uint, longitude: uint },
    certifications: (list 5 (string-ascii 32)),
    total-produced: uint,
    last-reading: uint,
    status: (string-ascii 16),
    registered-at: uint
  }
)

(define-map production-records
  { record-id: (buff 32) }
  {
    producer: principal,
    energy-amount: uint,
    energy-type: (string-ascii 16),
    timestamp: uint,
    source-data: (buff 64),
    verified: bool,
    verifier: (optional principal),
    grid-injection: bool,
    carbon-offset: uint
  }
)

(define-map energy-sources
  { source-id: (string-ascii 32) }
  {
    source-type: (string-ascii 16),
    efficiency-rating: uint,
    carbon-factor: uint,
    certification-body: (string-ascii 32),
    renewable: bool,
    active: bool
  }
)

(define-map daily-production
  { producer: principal, date: uint }
  {
    total-kwh: uint,
    peak-output: uint,
    efficiency: uint,
    weather-factor: uint,
    grid-contribution: uint
  }
)

;; Private Functions
(define-private (generate-producer-id (producer principal) (timestamp uint))
  (sha256 0x01)
)

(define-private (generate-record-id (producer principal) (amount uint) (timestamp uint))
  (sha256 0x02)
)

(define-private (calculate-carbon-offset (energy-amount uint) (energy-type (string-ascii 16)))
  (if (is-eq energy-type "solar")
    (* energy-amount u400) ;; 0.4 kg CO2 per kWh for solar
    (if (is-eq energy-type "wind")
      (* energy-amount u300) ;; 0.3 kg CO2 per kWh for wind
      (if (is-eq energy-type "hydro")
        (* energy-amount u200) ;; 0.2 kg CO2 per kWh for hydro
        (* energy-amount u100) ;; default 0.1 kg CO2 per kWh
      )
    )
  )
)

(define-private (validate-energy-type (energy-type (string-ascii 16)))
  (or (is-eq energy-type "solar")
      (or (is-eq energy-type "wind")
          (or (is-eq energy-type "hydro")
              (or (is-eq energy-type "geothermal")
                  (is-eq energy-type "biomass")))))
)

(define-private (calculate-efficiency (produced uint) (capacity uint) (hours uint))
  (if (> capacity u0)
    (/ (* produced u100) (* capacity hours))
    u0
  )
)

;; Public Functions

;; Register a new energy producer
(define-public (register-producer 
  (energy-type (string-ascii 16))
  (capacity uint)
  (location { latitude: uint, longitude: uint })
  (certifications (list 5 (string-ascii 32))))
  
  (let (
    (producer-id (generate-producer-id tx-sender u1))
  )
    (asserts! (validate-energy-type energy-type) err-invalid-data)
    (asserts! (> capacity u0) err-invalid-data)
    (asserts! (is-none (map-get? producers { producer: tx-sender })) err-already-exists)
    
    (map-set producers
      { producer: tx-sender }
      {
        producer-id: producer-id,
        energy-type: energy-type,
        capacity: capacity,
        location: location,
        certifications: certifications,
        total-produced: u0,
        last-reading: u0,
        status: "active",
        registered-at: u1
      }
    )
    
    (var-set total-registered-producers (+ (var-get total-registered-producers) u1))
    (ok { producer-id: producer-id })
  )
)

;; Record energy production
(define-public (record-production
  (energy-amount uint)
  (source-data (buff 64))
  (grid-injection bool))
  
  (let (
    (producer-info (unwrap! (map-get? producers { producer: tx-sender }) err-not-found))
    (record-id (generate-record-id tx-sender energy-amount u1))
    (carbon-offset (calculate-carbon-offset energy-amount (get energy-type producer-info)))
  )
    (asserts! (> energy-amount u0) err-invalid-data)
    
    (map-set production-records
      { record-id: record-id }
      {
        producer: tx-sender,
        energy-amount: energy-amount,
        energy-type: (get energy-type producer-info),
        timestamp: u1,
        source-data: source-data,
        verified: false,
        verifier: none,
        grid-injection: grid-injection,
        carbon-offset: carbon-offset
      }
    )
    
    ;; Update producer stats
    (map-set producers
      { producer: tx-sender }
      (merge producer-info {
        total-produced: (+ (get total-produced producer-info) energy-amount),
        last-reading: u1
      })
    )
    
    (var-set total-energy-produced (+ (var-get total-energy-produced) energy-amount))
    (ok { record-id: record-id })
  )
)

;; Verify energy production record
(define-public (verify-production (record-id (buff 32)) (verified bool))
  (let (
    (record (unwrap! (map-get? production-records { record-id: record-id }) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set production-records
      { record-id: record-id }
      (merge record {
        verified: verified,
        verifier: (some tx-sender)
      })
    )
    
    (if verified
      (var-set total-verified-production (+ (var-get total-verified-production) (get energy-amount record)))
      true
    )
    
    (ok verified)
  )
)

;; Record daily production summary
(define-public (record-daily-summary
  (date uint)
  (total-kwh uint)
  (peak-output uint)
  (weather-factor uint))
  
  (let (
    (producer-info (unwrap! (map-get? producers { producer: tx-sender }) err-not-found))
    (efficiency (calculate-efficiency total-kwh (get capacity producer-info) u24))
  )
    (asserts! (> total-kwh u0) err-invalid-data)
    (asserts! (<= peak-output (get capacity producer-info)) err-invalid-data)
    
    (map-set daily-production
      { producer: tx-sender, date: date }
      {
        total-kwh: total-kwh,
        peak-output: peak-output,
        efficiency: efficiency,
        weather-factor: weather-factor,
        grid-contribution: total-kwh
      }
    )
    
    (ok { efficiency: efficiency })
  )
)

;; Energy source registration removed for compatibility

;; Update producer status
(define-public (update-producer-status (producer principal) (status (string-ascii 16)))
  (let (
    (producer-info (unwrap! (map-get? producers { producer: producer }) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set producers
      { producer: producer }
      (merge producer-info { status: status })
    )
    
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-producer-info (producer principal))
  (map-get? producers { producer: producer })
)

(define-read-only (get-production-record (record-id (buff 32)))
  (map-get? production-records { record-id: record-id })
)

(define-read-only (get-energy-source (source-id (string-ascii 32)))
  (map-get? energy-sources { source-id: source-id })
)

(define-read-only (get-daily-production (producer principal) (date uint))
  (map-get? daily-production { producer: producer, date: date })
)

(define-read-only (get-total-producers)
  (var-get total-registered-producers)
)

(define-read-only (get-total-energy-produced)
  (var-get total-energy-produced)
)

(define-read-only (get-total-verified-production)
  (var-get total-verified-production)
)

(define-read-only (get-producer-efficiency (producer principal) (hours uint))
  (match (map-get? producers { producer: producer })
    producer-info 
      (if (> (get capacity producer-info) u0)
        (/ (* (get total-produced producer-info) u100) (* (get capacity producer-info) hours))
        u0
      )
    u0
  )
)

(define-read-only (is-producer-registered (producer principal))
  (is-some (map-get? producers { producer: producer }))
)

(define-read-only (get-carbon-offset-total (producer principal))
  (match (map-get? producers { producer: producer })
    producer-info
      (calculate-carbon-offset (get total-produced producer-info) (get energy-type producer-info))
    u0
  )
)