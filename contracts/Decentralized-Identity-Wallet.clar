(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_PERMISSION (err u103))
(define-constant ERR_EXPIRED (err u104))

(define-constant ERR_INSUFFICIENT_GUARDIANS (err u105))
(define-constant ERR_RECOVERY_NOT_ACTIVE (err u106))

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

(define-map trust-endorsements
  { endorser: principal, endorsed: principal }
  {
    score: uint,
    reason: (string-ascii 64),
    created-at: uint,
    updated-at: uint
  }
)

(define-map trust-scores
  { identity: principal }
  {
    total-score: uint,
    endorsement-count: uint,
    last-updated: uint
  }
)

(define-public (endorse-identity (endorsed principal) (score uint) (reason (string-ascii 64)))
  (let ((current-block stacks-block-height))
    (asserts! (is-some (map-get? identities { owner: endorsed })) ERR_NOT_FOUND)
    (asserts! (not (is-eq tx-sender endorsed)) ERR_UNAUTHORIZED)
    (asserts! (and (>= score u1) (<= score u10)) ERR_INVALID_PERMISSION)
    (let ((existing-endorsement (map-get? trust-endorsements { endorser: tx-sender, endorsed: endorsed })))
      (if (is-some existing-endorsement)
        (let ((old-score (get score (unwrap-panic existing-endorsement))))
          (map-set trust-endorsements
            { endorser: tx-sender, endorsed: endorsed }
            {
              score: score,
              reason: reason,
              created-at: (get created-at (unwrap-panic existing-endorsement)),
              updated-at: current-block
            }
          )
          (update-trust-score endorsed score old-score false)
        )
        (begin
          (map-set trust-endorsements
            { endorser: tx-sender, endorsed: endorsed }
            {
              score: score,
              reason: reason,
              created-at: current-block,
              updated-at: current-block
            }
          )
          (update-trust-score endorsed score u0 true)
        )
      )
    )
  )
)

(define-public (remove-endorsement (endorsed principal))
  (let ((endorsement (unwrap! (map-get? trust-endorsements { endorser: tx-sender, endorsed: endorsed }) ERR_NOT_FOUND)))
    (map-delete trust-endorsements { endorser: tx-sender, endorsed: endorsed })
    (update-trust-score endorsed u0 (get score endorsement) false)
  )
)

(define-private (update-trust-score (identity principal) (new-score uint) (old-score uint) (is-new bool))
  (let ((current-trust (default-to { total-score: u0, endorsement-count: u0, last-updated: u0 } 
                                   (map-get? trust-scores { identity: identity }))))
    (let ((score-diff (if (> new-score old-score) (- new-score old-score) (- old-score new-score)))
          (new-total (if (> new-score old-score) 
                        (+ (get total-score current-trust) score-diff)
                        (- (get total-score current-trust) score-diff)))
          (new-count (if is-new 
                        (+ (get endorsement-count current-trust) u1)
                        (if (is-eq new-score u0)
                           (- (get endorsement-count current-trust) u1)
                           (get endorsement-count current-trust)))))
      (map-set trust-scores
        { identity: identity }
        {
          total-score: new-total,
          endorsement-count: new-count,
          last-updated: stacks-block-height
        }
      )
      (ok true)
    )
  )
)

(define-read-only (get-trust-score (identity principal))
  (map-get? trust-scores { identity: identity })
)

(define-read-only (get-endorsement (endorser principal) (endorsed principal))
  (map-get? trust-endorsements { endorser: endorser, endorsed: endorsed })
)

(define-read-only (calculate-reputation-rating (identity principal))
  (let ((trust-data (map-get? trust-scores { identity: identity })))
    (if (is-some trust-data)
      (let ((data (unwrap-panic trust-data)))
        (if (> (get endorsement-count data) u0)
          (/ (get total-score data) (get endorsement-count data))
          u0
        )
      )
      u0
    )
  )
)

(define-map recovery-guardians
  { identity: principal, guardian: principal }
  { approved: bool, added-at: uint }
)

(define-map recovery-requests
  { identity: principal }
  {
    new-owner: principal,
    confirmations: uint,
    required-confirmations: uint,
    expires-at: uint,
    initiated-at: uint
  }
)

(define-map guardian-confirmations
  { identity: principal, guardian: principal }
  { confirmed: bool, confirmed-at: uint }
)

(define-public (add-recovery-guardian (guardian principal))
  (begin
    (asserts! (is-some (map-get? identities { owner: tx-sender })) ERR_NOT_FOUND)
    (asserts! (not (is-eq tx-sender guardian)) ERR_UNAUTHORIZED)
    (map-set recovery-guardians
      { identity: tx-sender, guardian: guardian }
      { approved: true, added-at: stacks-block-height }
    )
    (ok true)
  )
)

(define-public (remove-recovery-guardian (guardian principal))
  (begin
    (asserts! (is-some (map-get? recovery-guardians { identity: tx-sender, guardian: guardian })) ERR_NOT_FOUND)
    (map-delete recovery-guardians { identity: tx-sender, guardian: guardian })
    (ok true)
  )
)

(define-public (initiate-recovery (lost-identity principal) (new-owner principal))
  (let ((guardian-count (count-active-guardians lost-identity)))
    (asserts! (>= guardian-count u3) ERR_INSUFFICIENT_GUARDIANS)
    (asserts! (is-some (map-get? recovery-guardians { identity: lost-identity, guardian: tx-sender })) ERR_UNAUTHORIZED)
    (map-set recovery-requests
      { identity: lost-identity }
      {
        new-owner: new-owner,
        confirmations: u1,
        required-confirmations: (/ (* guardian-count u2) u3),
        expires-at: (+ stacks-block-height u1440),
        initiated-at: stacks-block-height
      }
    )
    (map-set guardian-confirmations
      { identity: lost-identity, guardian: tx-sender }
      { confirmed: true, confirmed-at: stacks-block-height }
    )
    (ok true)
  )
)

(define-public (confirm-recovery (lost-identity principal))
  (let ((recovery (unwrap! (map-get? recovery-requests { identity: lost-identity }) ERR_NOT_FOUND)))
    (asserts! (< stacks-block-height (get expires-at recovery)) ERR_EXPIRED)
    (asserts! (is-some (map-get? recovery-guardians { identity: lost-identity, guardian: tx-sender })) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? guardian-confirmations { identity: lost-identity, guardian: tx-sender })) ERR_ALREADY_EXISTS)
    (let ((new-confirmations (+ (get confirmations recovery) u1)))
      (map-set recovery-requests
        { identity: lost-identity }
        (merge recovery { confirmations: new-confirmations })
      )
      (map-set guardian-confirmations
        { identity: lost-identity, guardian: tx-sender }
        { confirmed: true, confirmed-at: stacks-block-height }
      )
      (if (>= new-confirmations (get required-confirmations recovery))
        (execute-recovery lost-identity (get new-owner recovery))
        (ok true)
      )
    )
  )
)

(define-private (execute-recovery (old-owner principal) (new-owner principal))
  (let ((identity (unwrap-panic (map-get? identities { owner: old-owner }))))
    (map-delete identities { owner: old-owner })
    (map-set identities
      { owner: new-owner }
      (merge identity { updated-at: stacks-block-height })
    )
    (map-delete recovery-requests { identity: old-owner })
    (ok true)
  )
)

(define-private (count-active-guardians (identity principal))
  u5
)

(define-read-only (get-recovery-status (identity principal))
  (map-get? recovery-requests { identity: identity })
)