(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_PERMISSION (err u103))
(define-constant ERR_EXPIRED (err u104))

(define-map identities
  { owner: principal }
  {
    did: (string-ascii 64),
    created-at: uint,
    updated-at: uint,
    is-active: bool
  }
)

(define-map identity-attributes
  { owner: principal, attribute-key: (string-ascii 32) }
  {
    value: (string-utf8 256),
    is-public: bool,
    created-at: uint,
    updated-at: uint
  }
)

(define-map access-permissions
  { owner: principal, requester: principal, attribute-key: (string-ascii 32) }
  {
    granted: bool,
    expires-at: uint,
    granted-at: uint
  }
)

(define-map verification-requests
  { id: uint }
  {
    requester: principal,
    owner: principal,
    attributes: (list 10 (string-ascii 32)),
    status: (string-ascii 16),
    created-at: uint,
    expires-at: uint
  }
)

(define-data-var next-request-id uint u1)

(define-public (create-identity (did (string-ascii 64)))
  (let ((current-block stacks-block-height))
    (if (is-some (map-get? identities { owner: tx-sender }))
      ERR_ALREADY_EXISTS
      (begin
        (map-set identities
          { owner: tx-sender }
          {
            did: did,
            created-at: current-block,
            updated-at: current-block,
            is-active: true
          }
        )
        (ok true)
      )
    )
  )
)

(define-public (update-identity-status (is-active bool))
  (let ((identity (unwrap! (map-get? identities { owner: tx-sender }) ERR_NOT_FOUND)))
    (map-set identities
      { owner: tx-sender }
      (merge identity { is-active: is-active, updated-at: stacks-block-height })
    )
    (ok true)
  )
)

(define-public (add-attribute (attribute-key (string-ascii 32)) (value (string-utf8 256)) (is-public bool))
  (let ((current-block stacks-block-height))
    (asserts! (is-some (map-get? identities { owner: tx-sender })) ERR_NOT_FOUND)
    (map-set identity-attributes
      { owner: tx-sender, attribute-key: attribute-key }
      {
        value: value,
        is-public: is-public,
        created-at: current-block,
        updated-at: current-block
      }
    )
    (ok true)
  )
)

(define-public (update-attribute (attribute-key (string-ascii 32)) (value (string-utf8 256)) (is-public bool))
  (let ((attribute (unwrap! (map-get? identity-attributes { owner: tx-sender, attribute-key: attribute-key }) ERR_NOT_FOUND)))
    (map-set identity-attributes
      { owner: tx-sender, attribute-key: attribute-key }
      (merge attribute { value: value, is-public: is-public, updated-at: stacks-block-height })
    )
    (ok true)
  )
)

(define-public (grant-access (requester principal) (attribute-key (string-ascii 32)) (duration uint))
  (let ((current-block stacks-block-height))
    (asserts! (is-some (map-get? identity-attributes { owner: tx-sender, attribute-key: attribute-key })) ERR_NOT_FOUND)
    (map-set access-permissions
      { owner: tx-sender, requester: requester, attribute-key: attribute-key }
      {
        granted: true,
        expires-at: (+ current-block duration),
        granted-at: current-block
      }
    )
    (ok true)
  )
)

(define-public (revoke-access (requester principal) (attribute-key (string-ascii 32)))
  (let ((permission (unwrap! (map-get? access-permissions { owner: tx-sender, requester: requester, attribute-key: attribute-key }) ERR_NOT_FOUND)))
    (map-set access-permissions
      { owner: tx-sender, requester: requester, attribute-key: attribute-key }
      (merge permission { granted: false })
    )
    (ok true)
  )
)

(define-public (request-verification (owner principal) (attributes (list 10 (string-ascii 32))) (duration uint))
  (let (
    (request-id (var-get next-request-id))
    (current-block stacks-block-height)
  )
    (asserts! (is-some (map-get? identities { owner: owner })) ERR_NOT_FOUND)
    (map-set verification-requests
      { id: request-id }
      {
        requester: tx-sender,
        owner: owner,
        attributes: attributes,
        status: "pending",
        created-at: current-block,
        expires-at: (+ current-block duration)
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

(define-public (approve-verification-request (request-id uint))
  (let ((request (unwrap! (map-get? verification-requests { id: request-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq (get owner request) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (< stacks-block-height (get expires-at request)) ERR_EXPIRED)
    (map-set verification-requests
      { id: request-id }
      (merge request { status: "approved" })
    )
    (ok true)
  )
)

(define-public (reject-verification-request (request-id uint))
  (let ((request (unwrap! (map-get? verification-requests { id: request-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq (get owner request) tx-sender) ERR_UNAUTHORIZED)
    (map-set verification-requests
      { id: request-id }
      (merge request { status: "rejected" })
    )
    (ok true)
  )
)

(define-read-only (get-identity (owner principal))
  (map-get? identities { owner: owner })
)

(define-read-only (get-attribute (owner principal) (attribute-key (string-ascii 32)))
  (let ((attribute (map-get? identity-attributes { owner: owner, attribute-key: attribute-key })))
    (if (is-some attribute)
      (let ((attr-data (unwrap-panic attribute)))
        (if (get is-public attr-data)
          attribute
          (if (is-eq owner tx-sender)
            attribute
            (let ((permission (map-get? access-permissions { owner: owner, requester: tx-sender, attribute-key: attribute-key })))
              (if (and (is-some permission) 
                       (get granted (unwrap-panic permission))
                       (> (get expires-at (unwrap-panic permission)) stacks-block-height))
                attribute
                none
              )
            )
          )
        )
      )
      none
    )
  )
)

(define-read-only (get-access-permission (owner principal) (requester principal) (attribute-key (string-ascii 32)))
  (map-get? access-permissions { owner: owner, requester: requester, attribute-key: attribute-key })
)

(define-read-only (get-verification-request (request-id uint))
  (map-get? verification-requests { id: request-id })
)

(define-read-only (has-valid-access (owner principal) (attribute-key (string-ascii 32)))
  (let ((permission (map-get? access-permissions { owner: owner, requester: tx-sender, attribute-key: attribute-key })))
    (if (is-some permission)
      (let ((perm-data (unwrap-panic permission)))
        (and (get granted perm-data) (> (get expires-at perm-data) stacks-block-height))
      )
      false
    )
  )
)

(define-read-only (is-identity-active (owner principal))
  (let ((identity (map-get? identities { owner: owner })))
    (if (is-some identity)
      (get is-active (unwrap-panic identity))
      false
    )
  )
)

(define-read-only (get-next-request-id)
  (var-get next-request-id)
)
