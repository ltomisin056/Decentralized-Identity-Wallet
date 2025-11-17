(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_INPUT (err u102))

(define-constant ACTION_IDENTITY_CREATED "identity-created")
(define-constant ACTION_ATTRIBUTE_ADDED "attribute-added")
(define-constant ACTION_ATTRIBUTE_UPDATED "attribute-updated")
(define-constant ACTION_ACCESS_GRANTED "access-granted")
(define-constant ACTION_ACCESS_REVOKED "access-revoked")
(define-constant ACTION_VERIFICATION_REQUESTED "verification-requested")
(define-constant ACTION_VERIFICATION_APPROVED "verification-approved")
(define-constant ACTION_VERIFICATION_REJECTED "verification-rejected")

(define-map activity-logs
  { log-id: uint }
  {
    identity-owner: principal,
    actor: principal,
    action-type: (string-ascii 32),
    target-attribute: (optional (string-ascii 32)),
    target-principal: (optional principal),
    block-height: uint,
    timestamp: uint
  }
)

(define-data-var next-log-id uint u1)

(define-public (log-activity 
    (identity-owner principal) 
    (action-type (string-ascii 32)) 
    (target-attribute (optional (string-ascii 32)))
    (target-principal (optional principal)))
  (let ((log-id (var-get next-log-id)))
    (map-set activity-logs
      { log-id: log-id }
      {
        identity-owner: identity-owner,
        actor: tx-sender,
        action-type: action-type,
        target-attribute: target-attribute,
        target-principal: target-principal,
        block-height: stacks-block-height,
        timestamp: stacks-block-height
      }
    )
    (var-set next-log-id (+ log-id u1))
    (ok log-id)
  )
)

(define-read-only (get-activity-log (log-id uint))
  (map-get? activity-logs { log-id: log-id })
)

(define-read-only (get-total-activity-count)
  (- (var-get next-log-id) u1)
)

(define-read-only (get-recent-activities (count uint))
  (let ((total (var-get next-log-id)))
    (ok (get-logs-range (if (> total count) (- total count) u1) total))
  )
)

(define-private (get-logs-range (start-id uint) (end-id uint))
  (map get-activity-log (list start-id))
)
