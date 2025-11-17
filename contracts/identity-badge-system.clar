(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_EXPIRED (err u104))
(define-constant ERR_INVALID_INPUT (err u105))

(define-map badge-types
  { badge-id: (string-ascii 32) }
  {
    name: (string-utf8 64),
    issuer-authority: principal,
    requires-renewal: bool,
    created-at: uint
  }
)

(define-map issued-badges
  { recipient: principal, badge-id: (string-ascii 32) }
  {
    issuer: principal,
    issued-at: uint,
    expires-at: uint,
    metadata: (string-utf8 256),
    is-visible: bool,
    is-revoked: bool
  }
)

(define-map badge-counts
  { recipient: principal }
  { total-badges: uint, active-badges: uint }
)

(define-data-var contract-admin principal tx-sender)

(define-public (register-badge-type 
    (badge-id (string-ascii 32)) 
    (name (string-utf8 64)) 
    (issuer-authority principal) 
    (requires-renewal bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? badge-types { badge-id: badge-id })) ERR_ALREADY_EXISTS)
    (map-set badge-types
      { badge-id: badge-id }
      {
        name: name,
        issuer-authority: issuer-authority,
        requires-renewal: requires-renewal,
        created-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (issue-badge 
    (recipient principal) 
    (badge-id (string-ascii 32)) 
    (duration uint) 
    (metadata (string-utf8 256)))
  (let ((badge-type (unwrap! (map-get? badge-types { badge-id: badge-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get issuer-authority badge-type)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? issued-badges { recipient: recipient, badge-id: badge-id })) ERR_ALREADY_EXISTS)
    (map-set issued-badges
      { recipient: recipient, badge-id: badge-id }
      {
        issuer: tx-sender,
        issued-at: stacks-block-height,
        expires-at: (+ stacks-block-height duration),
        metadata: metadata,
        is-visible: true,
        is-revoked: false
      }
    )
    (increment-badge-count recipient)
    (ok true)
  )
)

(define-public (revoke-badge (recipient principal) (badge-id (string-ascii 32)))
  (let ((badge (unwrap! (map-get? issued-badges { recipient: recipient, badge-id: badge-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get issuer badge)) ERR_UNAUTHORIZED)
    (map-set issued-badges
      { recipient: recipient, badge-id: badge-id }
      (merge badge { is-revoked: true })
    )
    (decrement-active-badge-count recipient)
    (ok true)
  )
)

(define-public (set-badge-visibility (badge-id (string-ascii 32)) (is-visible bool))
  (let ((badge (unwrap! (map-get? issued-badges { recipient: tx-sender, badge-id: badge-id }) ERR_NOT_FOUND)))
    (map-set issued-badges
      { recipient: tx-sender, badge-id: badge-id }
      (merge badge { is-visible: is-visible })
    )
    (ok true)
  )
)

(define-private (increment-badge-count (recipient principal))
  (let ((counts (default-to { total-badges: u0, active-badges: u0 } 
                            (map-get? badge-counts { recipient: recipient }))))
    (map-set badge-counts
      { recipient: recipient }
      {
        total-badges: (+ (get total-badges counts) u1),
        active-badges: (+ (get active-badges counts) u1)
      }
    )
  )
)

(define-private (decrement-active-badge-count (recipient principal))
  (let ((counts (unwrap-panic (map-get? badge-counts { recipient: recipient }))))
    (map-set badge-counts
      { recipient: recipient }
      (merge counts { active-badges: (- (get active-badges counts) u1) })
    )
  )
)

(define-read-only (get-badge (recipient principal) (badge-id (string-ascii 32)))
  (let ((badge (map-get? issued-badges { recipient: recipient, badge-id: badge-id })))
    (if (and (is-some badge) (get is-visible (unwrap-panic badge)))
      badge
      (if (is-eq tx-sender recipient) badge none)
    )
  )
)

(define-read-only (verify-badge (recipient principal) (badge-id (string-ascii 32)))
  (let ((badge (map-get? issued-badges { recipient: recipient, badge-id: badge-id })))
    (if (is-some badge)
      (let ((badge-data (unwrap-panic badge)))
        (ok {
          is-valid: (and 
            (not (get is-revoked badge-data))
            (> (get expires-at badge-data) stacks-block-height)
          ),
          issuer: (get issuer badge-data),
          issued-at: (get issued-at badge-data),
          expires-at: (get expires-at badge-data)
        })
      )
      ERR_NOT_FOUND
    )
  )
)

(define-read-only (get-badge-type (badge-id (string-ascii 32)))
  (map-get? badge-types { badge-id: badge-id })
)

(define-read-only (get-recipient-badge-stats (recipient principal))
  (map-get? badge-counts { recipient: recipient })
)
