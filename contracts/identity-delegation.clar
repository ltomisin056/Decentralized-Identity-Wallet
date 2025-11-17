(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_EXPIRED (err u104))
(define-constant ERR_INVALID_PERMISSION (err u103))

(define-map identity-delegates
  { identity-owner: principal, delegate: principal }
  {
    permissions: uint,
    expires-at: uint,
    granted-at: uint,
    is-active: bool
  }
)

(define-map delegation-actions
  { action-id: uint }
  {
    delegate: principal,
    identity-owner: principal,
    action-type: (string-ascii 32),
    block-height: uint,
    success: bool
  }
)

(define-data-var next-action-id uint u1)

(define-constant PERMISSION_MANAGE_ATTRIBUTES u1)
(define-constant PERMISSION_GRANT_ACCESS u2) 
(define-constant PERMISSION_APPROVE_REQUESTS u4)
(define-constant PERMISSION_ALL u7)

(define-public (grant-delegation (delegate principal) (permissions uint) (duration uint))
  (let ((current-block stacks-block-height))
    (asserts! (not (is-eq tx-sender delegate)) ERR_UNAUTHORIZED)
    (asserts! (and (> permissions u0) (<= permissions PERMISSION_ALL)) ERR_INVALID_PERMISSION)
    (asserts! (> duration u0) ERR_INVALID_PERMISSION)
    (map-set identity-delegates
      { identity-owner: tx-sender, delegate: delegate }
      {
        permissions: permissions,
        expires-at: (+ current-block duration),
        granted-at: current-block,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (revoke-delegation (delegate principal))
  (let ((delegation (unwrap! (map-get? identity-delegates { identity-owner: tx-sender, delegate: delegate }) ERR_NOT_FOUND)))
    (map-set identity-delegates
      { identity-owner: tx-sender, delegate: delegate }
      (merge delegation { is-active: false })
    )
    (ok true)
  )
)

(define-public (create-delegation-request (identity-owner principal) (action-type (string-ascii 32)) (params (string-utf8 512)))
  (let ((delegation (unwrap! (get-valid-delegation identity-owner tx-sender (get-required-permission action-type)) ERR_UNAUTHORIZED)))
    (let ((action-id (var-get next-action-id)))
      (map-set delegation-actions
        { action-id: action-id }
        {
          delegate: tx-sender,
          identity-owner: identity-owner,
          action-type: action-type,
          block-height: stacks-block-height,
          success: true
        }
      )
      (var-set next-action-id (+ action-id u1))
      (ok action-id)
    )
  )
)

(define-public (execute-delegated-action (action-id uint) (target-function (string-ascii 32)) (param1 (optional (string-utf8 256))) (param2 (optional uint)))
  (let ((action (unwrap! (map-get? delegation-actions { action-id: action-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get identity-owner action)) ERR_UNAUTHORIZED)
    (asserts! (get success action) ERR_UNAUTHORIZED)
    (log-delegation-action (get action-type action) (get identity-owner action) true)
    (ok true)
  )
)

(define-private (get-required-permission (action-type (string-ascii 32)))
  (if (is-eq action-type "add-attribute")
    PERMISSION_MANAGE_ATTRIBUTES
    (if (is-eq action-type "grant-access")
      PERMISSION_GRANT_ACCESS
      (if (is-eq action-type "approve-verification")
        PERMISSION_APPROVE_REQUESTS
        PERMISSION_ALL
      )
    )
  )
)

(define-private (get-valid-delegation (identity-owner principal) (delegate principal) (required-permission uint))
  (let ((delegation (map-get? identity-delegates { identity-owner: identity-owner, delegate: delegate })))
    (if (is-some delegation)
      (let ((del-data (unwrap-panic delegation)))
        (if (and 
              (get is-active del-data)
              (> (get expires-at del-data) stacks-block-height)
              (>= (bit-and (get permissions del-data) required-permission) required-permission))
          (some del-data)
          none
        )
      )
      none
    )
  )
)

(define-private (log-delegation-action (action-type (string-ascii 32)) (identity-owner principal) (success bool))
  (let ((action-id (var-get next-action-id)))
    (map-set delegation-actions
      { action-id: action-id }
      {
        delegate: tx-sender,
        identity-owner: identity-owner,
        action-type: action-type,
        block-height: stacks-block-height,
        success: success
      }
    )
    (var-set next-action-id (+ action-id u1))
  )
)

(define-read-only (get-delegation (identity-owner principal) (delegate principal))
  (map-get? identity-delegates { identity-owner: identity-owner, delegate: delegate })
)

(define-read-only (has-delegation-permission (identity-owner principal) (delegate principal) (permission uint))
  (is-some (get-valid-delegation identity-owner delegate permission))
)

(define-read-only (get-delegation-action (action-id uint))
  (map-get? delegation-actions { action-id: action-id })
)
