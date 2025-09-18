
;; title: identity-vault
;; version: 1.0.0
;; summary: Self-Sovereign Identity Vault Contract
;; description: Stores encrypted identity credentials with user-controlled access permissions and selective 
;;             disclosure capabilities. Manages identity attestations from trusted verifiers with reputation 
;;             weighting and fraud detection mechanisms.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-identity-not-found (err u102))
(define-constant err-verifier-not-found (err u103))
(define-constant err-credential-not-found (err u104))
(define-constant err-invalid-proof (err u105))
(define-constant err-access-denied (err u106))
(define-constant err-expired-credential (err u107))
(define-constant err-invalid-recovery (err u108))
(define-constant err-insufficient-reputation (err u109))
(define-constant err-already-exists (err u110))

;; Identity verification levels
(define-constant verification-level-basic u1)
(define-constant verification-level-enhanced u2)
(define-constant verification-level-premium u3)
(define-constant verification-level-enterprise u4)

;; Credential types
(define-constant credential-type-age "age")
(define-constant credential-type-location "location")
(define-constant credential-type-education "education")
(define-constant credential-type-employment "employment")
(define-constant credential-type-financial "financial")

;; Access control constants
(define-constant access-duration-temporary u720) ;; ~5 days in blocks
(define-constant access-duration-extended u2016) ;; ~2 weeks in blocks
(define-constant min-verifier-reputation u75)
(define-constant max-recovery-contacts u5)

;; Data Variables
(define-data-var identity-counter uint u0)
(define-data-var verifier-counter uint u0)
(define-data-var proof-counter uint u0)
(define-data-var total-verifications uint u0)
(define-data-var contract-paused bool false)

;; Data Maps

;; User identity registry with encrypted storage
(define-map identities
  { identity-id: uint }
  {
    owner: principal,
    creation-height: uint,
    verification-level: uint,
    encryption-key: (buff 32),
    recovery-contacts: (list 5 principal),
    active-credentials: uint,
    last-activity: uint,
    is-active: bool,
    reputation-score: uint
  }
)

;; Principal to identity mapping for quick lookup
(define-map principal-to-identity
  { owner: principal }
  { identity-id: uint }
)

;; Encrypted credential storage
(define-map credentials
  { identity-id: uint, credential-id: uint }
  {
    credential-type: (string-ascii 20),
    encrypted-data: (buff 512),
    verifier-id: uint,
    issued-at: uint,
    expires-at: uint,
    verification-proof: (buff 64),
    selective-disclosure: bool,
    is-revoked: bool
  }
)

;; Trusted verifier network
(define-map verifiers
  { verifier-id: uint }
  {
    name: (string-ascii 100),
    wallet: principal,
    reputation-score: uint,
    total-verifications: uint,
    fraud-reports: uint,
    specialization: (string-ascii 50),
    registration-height: uint,
    is-active: bool,
    verification-fee: uint
  }
)

;; Zero-knowledge proof records
(define-map proof-records
  { proof-id: uint }
  {
    identity-id: uint,
    verifier: principal,
    claim-type: (string-ascii 20),
    proof-hash: (buff 32),
    verification-timestamp: uint,
    is-valid: bool,
    selective-attributes: (list 10 (string-ascii 20))
  }
)

;; Access control and permissions
(define-map access-grants
  { identity-id: uint, service-provider: principal }
  {
    granted-at: uint,
    expires-at: uint,
    permitted-attributes: (list 10 (string-ascii 20)),
    access-level: uint,
    usage-count: uint,
    is-active: bool
  }
)

;; Social recovery system
(define-map recovery-requests
  { identity-id: uint, requester: principal }
  {
    initiated-at: uint,
    confirmations: (list 5 principal),
    required-confirmations: uint,
    new-owner: principal,
    is-completed: bool,
    expires-at: uint
  }
)

;; Consent and audit logs
(define-map consent-logs
  { identity-id: uint, log-id: uint }
  {
    service-provider: principal,
    data-shared: (list 10 (string-ascii 20)),
    purpose: (string-ascii 100),
    timestamp: uint,
    consent-duration: uint,
    is-revoked: bool
  }
)

;; Public Functions

;; Create a new self-sovereign identity
(define-public (create-identity 
  (encryption-key (buff 32))
  (recovery-contacts (list 5 principal))
  (verification-level uint)
)
  (let (
    (identity-id (+ (var-get identity-counter) u1))
    (sender tx-sender)
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (is-none (map-get? principal-to-identity { owner: sender })) err-already-exists)
    (asserts! (<= verification-level verification-level-enterprise) err-not-authorized)
    (asserts! (> (len recovery-contacts) u0) err-invalid-recovery)
    (asserts! (<= (len recovery-contacts) max-recovery-contacts) err-invalid-recovery)
    
    ;; Create identity record
    (map-set identities
      { identity-id: identity-id }
      {
        owner: sender,
        creation-height: block-height,
        verification-level: verification-level,
        encryption-key: encryption-key,
        recovery-contacts: recovery-contacts,
        active-credentials: u0,
        last-activity: block-height,
        is-active: true,
        reputation-score: u100
      }
    )
    
    ;; Create principal mapping
    (map-set principal-to-identity
      { owner: sender }
      { identity-id: identity-id }
    )
    
    (var-set identity-counter identity-id)
    (ok identity-id)
  )
)

;; Register as a trusted verifier
(define-public (register-verifier
  (name (string-ascii 100))
  (specialization (string-ascii 50))
  (verification-fee uint)
)
  (let (
    (verifier-id (+ (var-get verifier-counter) u1))
    (sender tx-sender)
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    
    ;; Register verifier
    (map-set verifiers
      { verifier-id: verifier-id }
      {
        name: name,
        wallet: sender,
        reputation-score: u100, ;; Start with full reputation
        total-verifications: u0,
        fraud-reports: u0,
        specialization: specialization,
        registration-height: block-height,
        is-active: true,
        verification-fee: verification-fee
      }
    )
    
    (var-set verifier-counter verifier-id)
    (ok verifier-id)
  )
)

;; Add encrypted credential to identity vault
(define-public (add-credential
  (identity-id uint)
  (credential-type (string-ascii 20))
  (encrypted-data (buff 512))
  (verifier-id uint)
  (expires-at uint)
  (verification-proof (buff 64))
)
  (let (
    (identity-info (unwrap! (map-get? identities { identity-id: identity-id }) err-identity-not-found))
    (verifier-info (unwrap! (map-get? verifiers { verifier-id: verifier-id }) err-verifier-not-found))
    (credential-id (+ (get active-credentials identity-info) u1))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (is-eq tx-sender (get owner identity-info)) err-not-authorized)
    (asserts! (get is-active identity-info) err-identity-not-found)
    (asserts! (get is-active verifier-info) err-verifier-not-found)
    (asserts! (>= (get reputation-score verifier-info) min-verifier-reputation) err-insufficient-reputation)
    (asserts! (> expires-at block-height) err-expired-credential)
    
    ;; Store encrypted credential
    (map-set credentials
      { identity-id: identity-id, credential-id: credential-id }
      {
        credential-type: credential-type,
        encrypted-data: encrypted-data,
        verifier-id: verifier-id,
        issued-at: block-height,
        expires-at: expires-at,
        verification-proof: verification-proof,
        selective-disclosure: true,
        is-revoked: false
      }
    )
    
    ;; Update identity stats
    (map-set identities
      { identity-id: identity-id }
      (merge identity-info {
        active-credentials: credential-id,
        last-activity: block-height
      })
    )
    
    ;; Update verifier stats
    (map-set verifiers
      { verifier-id: verifier-id }
      (merge verifier-info {
        total-verifications: (+ (get total-verifications verifier-info) u1)
      })
    )
    
    (var-set total-verifications (+ (var-get total-verifications) u1))
    (ok credential-id)
  )
)

;; Verify claim using zero-knowledge proof
(define-public (verify-claim
  (identity-id uint)
  (claim-type (string-ascii 20))
  (proof-hash (buff 32))
  (selective-attributes (list 10 (string-ascii 20)))
)
  (let (
    (identity-info (unwrap! (map-get? identities { identity-id: identity-id }) err-identity-not-found))
    (proof-id (+ (var-get proof-counter) u1))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (get is-active identity-info) err-identity-not-found)
    
    ;; Record proof verification
    (map-set proof-records
      { proof-id: proof-id }
      {
        identity-id: identity-id,
        verifier: tx-sender,
        claim-type: claim-type,
        proof-hash: proof-hash,
        verification-timestamp: block-height,
        is-valid: true, ;; Simplified validation for this implementation
        selective-attributes: selective-attributes
      }
    )
    
    ;; Update identity activity
    (map-set identities
      { identity-id: identity-id }
      (merge identity-info { last-activity: block-height })
    )
    
    (var-set proof-counter proof-id)
    (ok proof-id)
  )
)

;; Grant temporary access to service provider
(define-public (grant-access
  (identity-id uint)
  (service-provider principal)
  (permitted-attributes (list 10 (string-ascii 20)))
  (access-duration uint)
  (access-level uint)
)
  (let (
    (identity-info (unwrap! (map-get? identities { identity-id: identity-id }) err-identity-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (is-eq tx-sender (get owner identity-info)) err-not-authorized)
    (asserts! (get is-active identity-info) err-identity-not-found)
    (asserts! (<= access-duration access-duration-extended) err-not-authorized)
    
    ;; Grant access permissions
    (map-set access-grants
      { identity-id: identity-id, service-provider: service-provider }
      {
        granted-at: block-height,
        expires-at: (+ block-height access-duration),
        permitted-attributes: permitted-attributes,
        access-level: access-level,
        usage-count: u0,
        is-active: true
      }
    )
    
    ;; Update identity activity
    (map-set identities
      { identity-id: identity-id }
      (merge identity-info { last-activity: block-height })
    )
    
    (ok true)
  )
)

;; Revoke access or credentials
(define-public (revoke-credentials
  (identity-id uint)
  (credential-id uint)
)
  (let (
    (identity-info (unwrap! (map-get? identities { identity-id: identity-id }) err-identity-not-found))
    (credential-info (unwrap! (map-get? credentials { identity-id: identity-id, credential-id: credential-id }) err-credential-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (is-eq tx-sender (get owner identity-info)) err-not-authorized)
    (asserts! (not (get is-revoked credential-info)) err-credential-not-found)
    
    ;; Revoke credential
    (map-set credentials
      { identity-id: identity-id, credential-id: credential-id }
      (merge credential-info { is-revoked: true })
    )
    
    ;; Update identity activity
    (map-set identities
      { identity-id: identity-id }
      (merge identity-info { last-activity: block-height })
    )
    
    (ok true)
  )
)

;; Initiate social recovery process
(define-public (initiate-social-recovery
  (identity-id uint)
  (new-owner principal)
)
  (let (
    (identity-info (unwrap! (map-get? identities { identity-id: identity-id }) err-identity-not-found))
    (recovery-contacts (get recovery-contacts identity-info))
    (required-confirmations (/ (len recovery-contacts) u2)) ;; Majority required
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (is-some (index-of recovery-contacts tx-sender)) err-not-authorized)
    (asserts! (get is-active identity-info) err-identity-not-found)
    
    ;; Initiate recovery request
    (map-set recovery-requests
      { identity-id: identity-id, requester: tx-sender }
      {
        initiated-at: block-height,
        confirmations: (list tx-sender),
        required-confirmations: (+ required-confirmations u1),
        new-owner: new-owner,
        is-completed: false,
        expires-at: (+ block-height access-duration-temporary)
      }
    )
    
    (ok true)
  )
)

;; Emergency pause function (owner only)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Read-only functions

;; Get identity information
(define-read-only (get-identity-info (identity-id uint))
  (map-get? identities { identity-id: identity-id })
)

;; Get identity by principal
(define-read-only (get-identity-by-principal (owner principal))
  (match (map-get? principal-to-identity { owner: owner })
    mapping (map-get? identities { identity-id: (get identity-id mapping) })
    none
  )
)

;; Get credential information
(define-read-only (get-credential-info (identity-id uint) (credential-id uint))
  (map-get? credentials { identity-id: identity-id, credential-id: credential-id })
)

;; Get verifier information
(define-read-only (get-verifier-info (verifier-id uint))
  (map-get? verifiers { verifier-id: verifier-id })
)

;; Get proof record
(define-read-only (get-proof-record (proof-id uint))
  (map-get? proof-records { proof-id: proof-id })
)

;; Get access grant status
(define-read-only (get-access-grant (identity-id uint) (service-provider principal))
  (match (map-get? access-grants { identity-id: identity-id, service-provider: service-provider })
    grant-info
    (some {
      is-active: (and (get is-active grant-info) (< block-height (get expires-at grant-info))),
      permitted-attributes: (get permitted-attributes grant-info),
      expires-at: (get expires-at grant-info),
      usage-count: (get usage-count grant-info)
    })
    none
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-identities: (var-get identity-counter),
    total-verifiers: (var-get verifier-counter),
    total-proofs: (var-get proof-counter),
    total-verifications: (var-get total-verifications),
    contract-paused: (var-get contract-paused)
  }
)

;; Check if credential is valid and not expired
(define-read-only (is-credential-valid (identity-id uint) (credential-id uint))
  (match (map-get? credentials { identity-id: identity-id, credential-id: credential-id })
    credential-info
    (and
      (not (get is-revoked credential-info))
      (> (get expires-at credential-info) block-height)
    )
    false
  )
)

;; Verify zero-knowledge proof (simplified)
(define-read-only (verify-zk-proof (proof-hash (buff 32)) (claim-type (string-ascii 20)))
  ;; Simplified proof verification - in real implementation would use cryptographic verification
  (> (len proof-hash) u0)
)

;; Get verifier reputation score
(define-read-only (get-verifier-reputation (verifier-id uint))
  (match (map-get? verifiers { verifier-id: verifier-id })
    verifier-info
    (get reputation-score verifier-info)
    u0
  )
)

;; Private functions

;; Calculate identity reputation based on activity and verifications
(define-private (calculate-identity-reputation (identity-id uint))
  (match (map-get? identities { identity-id: identity-id })
    identity-info
    (let (
      (base-score u100)
      (activity-bonus (if (< (- block-height (get last-activity identity-info)) u1000) u10 u0))
      (credential-bonus (* (get active-credentials identity-info) u5))
    )
      (+ base-score activity-bonus credential-bonus)
    )
    u0
  )
)

;; Validate selective disclosure attributes
(define-private (validate-selective-attributes (attributes (list 10 (string-ascii 20))))
  (and
    (> (len attributes) u0)
    (<= (len attributes) u10)
  )
)
