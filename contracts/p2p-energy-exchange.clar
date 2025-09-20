;; Distributed Renewable Energy Trading Platform - P2P Energy Exchange
;; Facilitates direct peer-to-peer energy trading between producers and consumers

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-invalid-data (err u203))
(define-constant err-insufficient-funds (err u204))
(define-constant err-insufficient-energy (err u205))
(define-constant err-offer-expired (err u206))
(define-constant err-offer-inactive (err u207))
(define-constant err-unauthorized (err u208))

;; Data Variables
(define-data-var total-energy-offers uint u0)
(define-data-var total-energy-traded uint u0)
(define-data-var total-trading-volume uint u0)
(define-data-var platform-fee-rate uint u50) ;; 0.5% in basis points

;; Data Maps
(define-map energy-offers
  { offer-id: (buff 32) }
  {
    producer: principal,
    energy-amount: uint,
    price-per-kwh: uint,
    energy-type: (string-ascii 16),
    location: { latitude: uint, longitude: uint },
    expiry-block: uint,
    min-purchase: uint,
    max-purchase: uint,
    available-amount: uint,
    status: (string-ascii 16),
    created-at: uint
  }
)

(define-map energy-purchases
  { transaction-id: (buff 32) }
  {
    offer-id: (buff 32),
    buyer: principal,
    seller: principal,
    energy-amount: uint,
    total-price: uint,
    price-per-kwh: uint,
    delivery-schedule: (string-ascii 32),
    delivery-status: (string-ascii 16),
    timestamp: uint,
    grid-fees: uint,
    platform-fees: uint
  }
)

(define-map consumer-profiles
  { consumer: principal }
  {
    consumer-id: (buff 32),
    energy-preferences: (list 5 (string-ascii 16)),
    max-price-willing: uint,
    monthly-consumption: uint,
    location: { latitude: uint, longitude: uint },
    sustainability-score: uint,
    total-purchased: uint,
    active-contracts: uint,
    registered-at: uint
  }
)

(define-map trading-contracts
  { contract-id: (buff 32) }
  {
    producer: principal,
    consumer: principal,
    energy-amount: uint,
    delivery-schedule: (string-ascii 32),
    price-per-kwh: uint,
    contract-duration: uint,
    auto-renewal: bool,
    start-date: uint,
    end-date: uint,
    status: (string-ascii 16)
  }
)

(define-map grid-balancing
  { grid-zone: (string-ascii 16), timestamp: uint }
  {
    total-supply: uint,
    total-demand: uint,
    peak-demand: uint,
    renewable-percentage: uint,
    grid-stability: uint,
    balancing-cost: uint,
    emergency-reserves: uint
  }
)

;; Private Functions
(define-private (generate-offer-id (producer principal) (amount uint) (timestamp uint))
  (sha256 0x03)
)

(define-private (generate-transaction-id (offer-id (buff 32)) (buyer principal))
  (sha256 (concat offer-id 0x01))
)

(define-private (calculate-distance-fee (producer-lat uint) (producer-lng uint) (consumer-lat uint) (consumer-lng uint))
  (let (
    (lat-diff (if (>= producer-lat consumer-lat) (- producer-lat consumer-lat) (- consumer-lat producer-lat)))
    (lng-diff (if (>= producer-lng consumer-lng) (- producer-lng consumer-lng) (- consumer-lng producer-lng)))
    (distance-factor (+ lat-diff lng-diff))
  )
    ;; Simple distance-based grid fee calculation
    (/ (* distance-factor u100) u10000)
  )
)

(define-private (calculate-platform-fee (total-price uint))
  (/ (* total-price (var-get platform-fee-rate)) u10000)
)

(define-private (validate-energy-type (energy-type (string-ascii 16)))
  (or (is-eq energy-type "solar")
      (or (is-eq energy-type "wind")
          (or (is-eq energy-type "hydro")
              (or (is-eq energy-type "geothermal")
                  (or (is-eq energy-type "biomass")
                      (is-eq energy-type "mixed"))))))
)

(define-private (calculate-time-of-use-multiplier (hour uint))
  (if (or (>= hour u17) (<= hour u21))
    u150 ;; Peak hours 1.5x multiplier
    (if (or (>= hour u9) (<= hour u17))
      u120 ;; Day hours 1.2x multiplier
      u80  ;; Off-peak hours 0.8x multiplier
    )
  )
)

;; Public Functions

;; Register as energy consumer
(define-public (register-consumer
  (energy-preferences (list 5 (string-ascii 16)))
  (max-price-willing uint)
  (monthly-consumption uint)
  (location { latitude: uint, longitude: uint }))
  
  (let (
    (consumer-id (generate-offer-id tx-sender monthly-consumption stacks-block-height))
  )
    (asserts! (> max-price-willing u0) err-invalid-data)
    (asserts! (> monthly-consumption u0) err-invalid-data)
    (asserts! (is-none (map-get? consumer-profiles { consumer: tx-sender })) err-already-exists)
    
    (map-set consumer-profiles
      { consumer: tx-sender }
      {
        consumer-id: consumer-id,
        energy-preferences: energy-preferences,
        max-price-willing: max-price-willing,
        monthly-consumption: monthly-consumption,
        location: location,
        sustainability-score: u0,
        total-purchased: u0,
        active-contracts: u0,
        registered-at: stacks-block-height
      }
    )
    
    (ok { consumer-id: consumer-id })
  )
)

;; Create energy offer
(define-public (create-energy-offer
  (energy-amount uint)
  (price-per-kwh uint)
  (energy-type (string-ascii 16))
  (location { latitude: uint, longitude: uint })
  (expiry-blocks uint)
  (min-purchase uint)
  (max-purchase uint))
  
  (let (
    (offer-id (generate-offer-id tx-sender energy-amount stacks-block-height))
  )
    (asserts! (> energy-amount u0) err-invalid-data)
    (asserts! (> price-per-kwh u0) err-invalid-data)
    (asserts! (validate-energy-type energy-type) err-invalid-data)
    (asserts! (<= min-purchase max-purchase) err-invalid-data)
    (asserts! (<= max-purchase energy-amount) err-invalid-data)
    
    (map-set energy-offers
      { offer-id: offer-id }
      {
        producer: tx-sender,
        energy-amount: energy-amount,
        price-per-kwh: price-per-kwh,
        energy-type: energy-type,
        location: location,
        expiry-block: (+ stacks-block-height expiry-blocks),
        min-purchase: min-purchase,
        max-purchase: max-purchase,
        available-amount: energy-amount,
        status: "active",
        created-at: stacks-block-height
      }
    )
    
    (var-set total-energy-offers (+ (var-get total-energy-offers) u1))
    (ok { offer-id: offer-id })
  )
)

;; Purchase energy from offer
(define-public (purchase-energy
  (offer-id (buff 32))
  (energy-amount uint)
  (delivery-schedule (string-ascii 32)))
  
  (let (
    (offer (unwrap! (map-get? energy-offers { offer-id: offer-id }) err-not-found))
    (consumer-info (unwrap! (map-get? consumer-profiles { consumer: tx-sender }) err-not-found))
    (transaction-id (generate-transaction-id offer-id tx-sender))
    (total-price (* energy-amount (get price-per-kwh offer)))
    (grid-fees (calculate-distance-fee 
                 (get latitude (get location offer))
                 (get longitude (get location offer))
                 (get latitude (get location consumer-info))
                 (get longitude (get location consumer-info))))
    (platform-fees (calculate-platform-fee total-price))
  )
    (asserts! (is-eq (get status offer) "active") err-offer-inactive)
    (asserts! (< stacks-block-height (get expiry-block offer)) err-offer-expired)
    (asserts! (>= energy-amount (get min-purchase offer)) err-invalid-data)
    (asserts! (<= energy-amount (get max-purchase offer)) err-invalid-data)
    (asserts! (<= energy-amount (get available-amount offer)) err-insufficient-energy)
    (asserts! (<= (get price-per-kwh offer) (get max-price-willing consumer-info)) err-invalid-data)
    
    ;; Record the purchase
    (map-set energy-purchases
      { transaction-id: transaction-id }
      {
        offer-id: offer-id,
        buyer: tx-sender,
        seller: (get producer offer),
        energy-amount: energy-amount,
        total-price: total-price,
        price-per-kwh: (get price-per-kwh offer),
        delivery-schedule: delivery-schedule,
        delivery-status: "scheduled",
        timestamp: stacks-block-height,
        grid-fees: grid-fees,
        platform-fees: platform-fees
      }
    )
    
    ;; Update offer availability
    (map-set energy-offers
      { offer-id: offer-id }
      (merge offer {
        available-amount: (- (get available-amount offer) energy-amount),
        status: (if (is-eq (- (get available-amount offer) energy-amount) u0) "sold" "active")
      })
    )
    
    ;; Update consumer stats
    (map-set consumer-profiles
      { consumer: tx-sender }
      (merge consumer-info {
        total-purchased: (+ (get total-purchased consumer-info) energy-amount),
        sustainability-score: (+ (get sustainability-score consumer-info) 
                                (if (or (is-eq (get energy-type offer) "solar") 
                                       (is-eq (get energy-type offer) "wind")) u10 u5))
      })
    )
    
    ;; Update global stats
    (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
    (var-set total-trading-volume (+ (var-get total-trading-volume) total-price))
    
    (ok { transaction-id: transaction-id, total-cost: (+ total-price grid-fees platform-fees) })
  )
)

;; Create long-term trading contract
(define-public (create-trading-contract
  (consumer principal)
  (energy-amount uint)
  (delivery-schedule (string-ascii 32))
  (price-per-kwh uint)
  (contract-duration uint)
  (auto-renewal bool))
  
  (let (
    (contract-id (generate-offer-id tx-sender energy-amount stacks-block-height))
  )
    (asserts! (> energy-amount u0) err-invalid-data)
    (asserts! (> price-per-kwh u0) err-invalid-data)
    (asserts! (> contract-duration u0) err-invalid-data)
    (asserts! (is-some (map-get? consumer-profiles { consumer: consumer })) err-not-found)
    
    (map-set trading-contracts
      { contract-id: contract-id }
      {
        producer: tx-sender,
        consumer: consumer,
        energy-amount: energy-amount,
        delivery-schedule: delivery-schedule,
        price-per-kwh: price-per-kwh,
        contract-duration: contract-duration,
        auto-renewal: auto-renewal,
        start-date: stacks-block-height,
        end-date: (+ stacks-block-height contract-duration),
        status: "pending"
      }
    )
    
    (ok { contract-id: contract-id })
  )
)

;; Accept trading contract
(define-public (accept-trading-contract (contract-id (buff 32)))
  (let (
    (contract (unwrap! (map-get? trading-contracts { contract-id: contract-id }) err-not-found))
    (consumer-info (unwrap! (map-get? consumer-profiles { consumer: tx-sender }) err-not-found))
  )
    (asserts! (is-eq (get consumer contract) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status contract) "pending") err-invalid-data)
    
    (map-set trading-contracts
      { contract-id: contract-id }
      (merge contract { status: "active" })
    )
    
    (map-set consumer-profiles
      { consumer: tx-sender }
      (merge consumer-info {
        active-contracts: (+ (get active-contracts consumer-info) u1)
      })
    )
    
    (ok true)
  )
)

;; Update delivery status
(define-public (update-delivery-status 
  (transaction-id (buff 32))
  (delivery-status (string-ascii 16)))
  
  (let (
    (purchase (unwrap! (map-get? energy-purchases { transaction-id: transaction-id }) err-not-found))
  )
    (asserts! (or (is-eq tx-sender (get seller purchase)) 
                  (is-eq tx-sender contract-owner)) err-unauthorized)
    
    (map-set energy-purchases
      { transaction-id: transaction-id }
      (merge purchase { delivery-status: delivery-status })
    )
    
    (ok true)
  )
)

;; Record grid balancing data
(define-public (record-grid-balancing
  (grid-zone (string-ascii 16))
  (total-supply uint)
  (total-demand uint)
  (peak-demand uint)
  (renewable-percentage uint))
  
  (asserts! (is-eq tx-sender contract-owner) err-owner-only)
  
  (let (
    (grid-stability (if (>= total-supply total-demand) u100 (/ (* total-supply u100) total-demand)))
  )
    (map-set grid-balancing
      { grid-zone: grid-zone, timestamp: stacks-block-height }
      {
        total-supply: total-supply,
        total-demand: total-demand,
        peak-demand: peak-demand,
        renewable-percentage: renewable-percentage,
        grid-stability: grid-stability,
        balancing-cost: (if (< grid-stability u95) u1000 u0),
        emergency-reserves: (if (> total-supply total-demand) (- total-supply total-demand) u0)
      }
    )
    
    (ok true)
  )
)

;; Update platform fee rate
(define-public (update-platform-fee-rate (new-rate uint))
  (asserts! (is-eq tx-sender contract-owner) err-owner-only)
  (asserts! (<= new-rate u500) err-invalid-data) ;; Max 5% fee
  
  (var-set platform-fee-rate new-rate)
  (ok new-rate)
)

;; Read-only Functions

(define-read-only (get-energy-offer (offer-id (buff 32)))
  (map-get? energy-offers { offer-id: offer-id })
)

(define-read-only (get-energy-purchase (transaction-id (buff 32)))
  (map-get? energy-purchases { transaction-id: transaction-id })
)

(define-read-only (get-consumer-profile (consumer principal))
  (map-get? consumer-profiles { consumer: consumer })
)

(define-read-only (get-trading-contract (contract-id (buff 32)))
  (map-get? trading-contracts { contract-id: contract-id })
)

(define-read-only (get-grid-balancing (grid-zone (string-ascii 16)) (timestamp uint))
  (map-get? grid-balancing { grid-zone: grid-zone, timestamp: timestamp })
)

(define-read-only (get-total-energy-offers)
  (var-get total-energy-offers)
)

(define-read-only (get-total-energy-traded)
  (var-get total-energy-traded)
)

(define-read-only (get-total-trading-volume)
  (var-get total-trading-volume)
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (calculate-total-cost 
  (energy-amount uint) 
  (price-per-kwh uint)
  (producer-location { latitude: uint, longitude: uint })
  (consumer-location { latitude: uint, longitude: uint }))
  
  (let (
    (base-price (* energy-amount price-per-kwh))
    (grid-fees (calculate-distance-fee 
                 (get latitude producer-location)
                 (get longitude producer-location)
                 (get latitude consumer-location)
                 (get longitude consumer-location)))
    (platform-fees (calculate-platform-fee base-price))
  )
    {
      base-price: base-price,
      grid-fees: grid-fees,
      platform-fees: platform-fees,
      total-cost: (+ base-price grid-fees platform-fees)
    }
  )
)

(define-read-only (get-market-price-range (energy-type (string-ascii 16)))
  ;; This would typically query active offers for price discovery
  (if (is-eq energy-type "solar")
    { min-price: u45, max-price: u85, average-price: u65 }
    (if (is-eq energy-type "wind")
      { min-price: u40, max-price: u75, average-price: u58 }
      { min-price: u50, max-price: u90, average-price: u70 }
    )
  )
)