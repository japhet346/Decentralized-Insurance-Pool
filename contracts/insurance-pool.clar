;; Decentralized Insurance Pool Contract
;; A mutual insurance system with risk assessment, claim voting, and dynamic premiums

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-member (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-claim-not-found (err u103))
(define-constant err-already-voted (err u104))
(define-constant err-voting-closed (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-pool-not-found (err u107))
(define-constant err-already-member (err u108))

;; Data Variables
(define-data-var next-pool-id uint u1)
(define-data-var next-claim-id uint u1)

;; Data Maps
(define-map pools
  { pool-id: uint }
  {
    name: (string-ascii 64),
    total-funds: uint,
    member-count: uint,
    base-premium: uint,
    risk-multiplier: uint,
    created-at: uint
  })

(define-map pool-members
  { pool-id: uint, member: principal }
  {
    premium-paid: uint,
    risk-score: uint,
    joined-at: uint,
    active: bool
  })

(define-map claims
  { claim-id: uint }
  {
    pool-id: uint,
    claimant: principal,
    amount: uint,
    description: (string-ascii 256),
    votes-for: uint,
    votes-against: uint,
    total-voters: uint,
    status: (string-ascii 16),
    created-at: uint,
    voting-deadline: uint
  })

(define-map claim-votes
  { claim-id: uint, voter: principal }
  { vote: bool, voted-at: uint })

;; Pool Management Functions

(define-public (create-pool (name (string-ascii 64)) (base-premium uint))
  (let ((pool-id (var-get next-pool-id)))
    (asserts! (> base-premium u0) (err err-invalid-amount))
    (map-set pools
      { pool-id: pool-id }
      {
        name: name,
        total-funds: u0,
        member-count: u0,
        base-premium: base-premium,
        risk-multiplier: u100,
        created-at: stacks-block-height
      })
    (var-set next-pool-id (+ pool-id u1))
    (ok pool-id)))

(define-public (join-pool (pool-id uint) (initial-premium uint))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found)))
        (member-exists (map-get? pool-members { pool-id: pool-id, member: tx-sender })))
    (asserts! (is-none member-exists) (err err-already-member))
    (asserts! (>= initial-premium (get base-premium pool)) (err err-invalid-amount))
    (unwrap! (stx-transfer? initial-premium tx-sender (as-contract tx-sender)) (err err-insufficient-funds))
    (map-set pool-members
      { pool-id: pool-id, member: tx-sender }
      {
        premium-paid: initial-premium,
        risk-score: u50,
        joined-at: stacks-block-height,
        active: true
      })
    (map-set pools
      { pool-id: pool-id }
      (merge pool {
        total-funds: (+ (get total-funds pool) initial-premium),
        member-count: (+ (get member-count pool) u1)
      }))
    (ok true)))

(define-public (pay-premium (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found)))
        (member (unwrap! (map-get? pool-members { pool-id: pool-id, member: tx-sender })
                         (err err-not-member))))
    (asserts! (get active member) (err err-not-member))
    (asserts! (> amount u0) (err err-invalid-amount))
    (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) (err err-insufficient-funds))
    (map-set pool-members
      { pool-id: pool-id, member: tx-sender }
      (merge member { premium-paid: (+ (get premium-paid member) amount) }))
    (map-set pools
      { pool-id: pool-id }
      (merge pool { total-funds: (+ (get total-funds pool) amount) }))
    (ok true)))

;; Claim Management Functions

(define-public (submit-claim (pool-id uint) (amount uint) (description (string-ascii 256)))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found)))
        (member (unwrap! (map-get? pool-members { pool-id: pool-id, member: tx-sender })
                         (err err-not-member)))
        (claim-id (var-get next-claim-id)))
    (asserts! (get active member) (err err-not-member))
    (asserts! (> amount u0) (err err-invalid-amount))
    (asserts! (<= amount (get total-funds pool)) (err err-insufficient-funds))
    (map-set claims
      { claim-id: claim-id }
      {
        pool-id: pool-id,
        claimant: tx-sender,
        amount: amount,
        description: description,
        votes-for: u0,
        votes-against: u0,
        total-voters: u0,
        status: "pending",
        created-at: stacks-block-height,
        voting-deadline: (+ stacks-block-height u144) ;; ~24 hours
      })
    (var-set next-claim-id (+ claim-id u1))
    (ok claim-id)))

(define-public (vote-on-claim (claim-id uint) (approve bool))
  (let ((claim (unwrap! (map-get? claims { claim-id: claim-id }) (err err-claim-not-found)))
        (existing-vote (map-get? claim-votes { claim-id: claim-id, voter: tx-sender }))
        (pool-id (get pool-id claim))
        (member (unwrap! (map-get? pool-members { pool-id: pool-id, member: tx-sender })
                         (err err-not-member))))
    (asserts! (is-none existing-vote) (err err-already-voted))
    (asserts! (get active member) (err err-not-member))
    (asserts! (< stacks-block-height (get voting-deadline claim)) (err err-voting-closed))
    (asserts! (is-eq (get status claim) "pending") (err err-voting-closed))

    (map-set claim-votes
      { claim-id: claim-id, voter: tx-sender }
      { vote: approve, voted-at: stacks-block-height })

    (let ((new-votes-for (if approve (+ (get votes-for claim) u1) (get votes-for claim)))
          (new-votes-against (if approve (get votes-against claim) (+ (get votes-against claim) u1)))
          (new-total-voters (+ (get total-voters claim) u1)))
      (map-set claims
        { claim-id: claim-id }
        (merge claim {
          votes-for: new-votes-for,
          votes-against: new-votes-against,
          total-voters: new-total-voters
        }))
      (ok true))))

(define-public (finalize-claim (claim-id uint))
  (let ((claim (unwrap! (map-get? claims { claim-id: claim-id }) (err err-claim-not-found)))
        (pool-id (get pool-id claim))
        (pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found))))
    (asserts! (>= stacks-block-height (get voting-deadline claim)) (err err-voting-closed))
    (asserts! (is-eq (get status claim) "pending") (err err-voting-closed))

    (let ((approved (> (get votes-for claim) (get votes-against claim)))
          (claim-amount (get amount claim))
          (claimant (get claimant claim)))
      (if approved
        (begin
          (unwrap! (as-contract (stx-transfer? claim-amount tx-sender claimant)) (err err-insufficient-funds))
          (map-set pools
            { pool-id: pool-id }
            (merge pool { total-funds: (- (get total-funds pool) claim-amount) }))
          (map-set claims
            { claim-id: claim-id }
            (merge claim { status: "approved" })))
        (map-set claims
          { claim-id: claim-id }
          (merge claim { status: "rejected" })))
      (ok approved))))

;; Risk Assessment Functions

(define-public (update-risk-score (pool-id uint) (member principal) (new-score uint))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found)))
        (member-data (unwrap! (map-get? pool-members { pool-id: pool-id, member: member })
                              (err err-not-member))))
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (<= new-score u100) (err err-invalid-amount))
    (map-set pool-members
      { pool-id: pool-id, member: member }
      (merge member-data { risk-score: new-score }))
    (ok true)))

(define-public (adjust-pool-multiplier (pool-id uint) (new-multiplier uint))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found))))
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (> new-multiplier u0) (err err-invalid-amount))
    (map-set pools
      { pool-id: pool-id }
      (merge pool { risk-multiplier: new-multiplier }))
    (ok true)))

;; Read-only Functions

(define-read-only (get-pool (pool-id uint))
  (map-get? pools { pool-id: pool-id }))

(define-read-only (get-member (pool-id uint) (member principal))
  (map-get? pool-members { pool-id: pool-id, member: member }))

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id }))

(define-read-only (get-member-vote (claim-id uint) (voter principal))
  (map-get? claim-votes { claim-id: claim-id, voter: voter }))

(define-read-only (calculate-premium (pool-id uint) (member principal))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found)))
        (member-data (unwrap! (map-get? pool-members { pool-id: pool-id, member: member })
                              (err err-not-member))))
    (ok (* (get base-premium pool)
           (get risk-multiplier pool)
           (get risk-score member-data)
           u1))))

(define-read-only (get-pool-stats (pool-id uint))
  (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) (err err-pool-not-found))))
    (ok {
      total-funds: (get total-funds pool),
      member-count: (get member-count pool),
      avg-premium: (if (> (get member-count pool) u0)
                      (/ (get total-funds pool) (get member-count pool))
                      u0)
    })))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))
