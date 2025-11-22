;; Hand Hygiene Monitor
;; Observe hygiene compliance, provide immediate feedback, track performance, implement improvement strategies, and reduce infections

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-already-exists (err u105))

;; Compliance status
(define-constant compliance-pass u1)
(define-constant compliance-fail u2)
(define-constant compliance-not-observed u3)

;; Opportunity types
(define-constant opportunity-before-patient u1)
(define-constant opportunity-after-patient u2)
(define-constant opportunity-before-procedure u3)
(define-constant opportunity-after-body-fluid u4)
(define-constant opportunity-after-environment u5)

;; Intervention types
(define-constant intervention-immediate-feedback u1)
(define-constant intervention-training u2)
(define-constant intervention-system-change u3)

;; Data Variables
(define-data-var observation-counter uint u0)
(define-data-var intervention-counter uint u0)
(define-data-var healthcare-worker-counter uint u0)
(define-data-var facility-compliance-target uint u90)

;; Data Maps

;; Healthcare worker registry
(define-map healthcare-workers
  { worker-id: principal }
  {
    name: (string-ascii 100),
    role: (string-ascii 50),
    department: (string-ascii 100),
    total-observations: uint,
    compliant-observations: uint,
    registered-date: uint,
    is-active: bool
  }
)

;; Observations
(define-map observations
  { observation-id: uint }
  {
    worker-id: principal,
    observer-id: principal,
    opportunity-type: uint,
    compliance-status: uint,
    location: (string-ascii 100),
    observation-date: uint,
    feedback-provided: bool,
    notes: (string-utf8 500)
  }
)

;; Interventions
(define-map interventions
  { intervention-id: uint }
  {
    worker-id: (optional principal),
    department: (string-ascii 100),
    intervention-type: uint,
    description: (string-utf8 500),
    implemented-by: principal,
    implementation-date: uint,
    target-completion-date: uint,
    is-completed: bool,
    completion-date: (optional uint)
  }
)

;; Department performance
(define-map department-stats
  { department: (string-ascii 100) }
  {
    total-observations: uint,
    compliant-observations: uint,
    last-audit-date: uint,
    compliance-rate: uint
  }
)

;; Observer registry
(define-map observers
  { observer-id: principal }
  {
    name: (string-ascii 100),
    certified: bool,
    total-observations: uint,
    registered-date: uint
  }
)

;; Read-only functions

;; Get healthcare worker details
(define-read-only (get-healthcare-worker (worker-id principal))
  (ok (map-get? healthcare-workers { worker-id: worker-id }))
)

;; Get observation details
(define-read-only (get-observation (observation-id uint))
  (ok (map-get? observations { observation-id: observation-id }))
)

;; Get intervention details
(define-read-only (get-intervention (intervention-id uint))
  (ok (map-get? interventions { intervention-id: intervention-id }))
)

;; Get department statistics
(define-read-only (get-department-stats (department (string-ascii 100)))
  (ok (map-get? department-stats { department: department }))
)

;; Get observer details
(define-read-only (get-observer (observer-id principal))
  (ok (map-get? observers { observer-id: observer-id }))
)

;; Calculate compliance rate for worker
(define-read-only (get-worker-compliance-rate (worker-id principal))
  (match (map-get? healthcare-workers { worker-id: worker-id })
    worker-data
      (if (> (get total-observations worker-data) u0)
        (ok (/ (* (get compliant-observations worker-data) u100) (get total-observations worker-data)))
        (ok u0)
      )
    (err err-not-found)
  )
)

;; Get counters
(define-read-only (get-observation-counter)
  (ok (var-get observation-counter))
)

(define-read-only (get-intervention-counter)
  (ok (var-get intervention-counter))
)

(define-read-only (get-compliance-target)
  (ok (var-get facility-compliance-target))
)

;; Public functions

;; Register healthcare worker
(define-public (register-healthcare-worker
  (worker-id principal)
  (name (string-ascii 100))
  (role (string-ascii 50))
  (department (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-none (map-get? healthcare-workers { worker-id: worker-id })) err-already-exists)
    
    (map-set healthcare-workers
      { worker-id: worker-id }
      {
        name: name,
        role: role,
        department: department,
        total-observations: u0,
        compliant-observations: u0,
        registered-date: block-height,
        is-active: true
      }
    )
    (var-set healthcare-worker-counter (+ (var-get healthcare-worker-counter) u1))
    (ok true)
  )
)

;; Register observer
(define-public (register-observer
  (observer-id principal)
  (name (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set observers
      { observer-id: observer-id }
      {
        name: name,
        certified: true,
        total-observations: u0,
        registered-date: block-height
      }
    )
    (ok true)
  )
)

;; Record observation
(define-public (record-observation
  (worker-id principal)
  (opportunity-type uint)
  (compliance-status uint)
  (location (string-ascii 100))
  (feedback-provided bool)
  (notes (string-utf8 500)))
  (let
    (
      (observation-id (+ (var-get observation-counter) u1))
      (worker-data (unwrap! (map-get? healthcare-workers { worker-id: worker-id }) err-not-found))
      (observer-data (unwrap! (map-get? observers { observer-id: tx-sender }) err-unauthorized))
      (dept-data (default-to 
        { total-observations: u0, compliant-observations: u0, last-audit-date: u0, compliance-rate: u0 }
        (map-get? department-stats { department: (get department worker-data) })
      ))
    )
    
    ;; Validate inputs
    (asserts! (get certified observer-data) err-unauthorized)
    (asserts! (<= opportunity-type opportunity-after-environment) err-invalid-input)
    (asserts! (<= compliance-status compliance-not-observed) err-invalid-input)
    
    ;; Create observation
    (map-set observations
      { observation-id: observation-id }
      {
        worker-id: worker-id,
        observer-id: tx-sender,
        opportunity-type: opportunity-type,
        compliance-status: compliance-status,
        location: location,
        observation-date: block-height,
        feedback-provided: feedback-provided,
        notes: notes
      }
    )
    
    ;; Update worker stats
    (map-set healthcare-workers
      { worker-id: worker-id }
      (merge worker-data {
        total-observations: (+ (get total-observations worker-data) u1),
        compliant-observations: (if (is-eq compliance-status compliance-pass)
          (+ (get compliant-observations worker-data) u1)
          (get compliant-observations worker-data)
        )
      })
    )
    
    ;; Update observer stats
    (map-set observers
      { observer-id: tx-sender }
      (merge observer-data {
        total-observations: (+ (get total-observations observer-data) u1)
      })
    )
    
    ;; Update department stats
    (map-set department-stats
      { department: (get department worker-data) }
      {
        total-observations: (+ (get total-observations dept-data) u1),
        compliant-observations: (if (is-eq compliance-status compliance-pass)
          (+ (get compliant-observations dept-data) u1)
          (get compliant-observations dept-data)
        ),
        last-audit-date: block-height,
        compliance-rate: (if (> (+ (get total-observations dept-data) u1) u0)
          (/ (* (if (is-eq compliance-status compliance-pass)
                  (+ (get compliant-observations dept-data) u1)
                  (get compliant-observations dept-data)
                ) u100)
             (+ (get total-observations dept-data) u1))
          u0
        )
      }
    )
    
    (var-set observation-counter observation-id)
    (ok observation-id)
  )
)

;; Create intervention
(define-public (create-intervention
  (worker-id (optional principal))
  (department (string-ascii 100))
  (intervention-type uint)
  (description (string-utf8 500))
  (target-completion-date uint))
  (let
    (
      (intervention-id (+ (var-get intervention-counter) u1))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= intervention-type intervention-system-change) err-invalid-input)
    (asserts! (> target-completion-date block-height) err-invalid-input)
    
    (map-set interventions
      { intervention-id: intervention-id }
      {
        worker-id: worker-id,
        department: department,
        intervention-type: intervention-type,
        description: description,
        implemented-by: tx-sender,
        implementation-date: block-height,
        target-completion-date: target-completion-date,
        is-completed: false,
        completion-date: none
      }
    )
    
    (var-set intervention-counter intervention-id)
    (ok intervention-id)
  )
)

;; Complete intervention
(define-public (complete-intervention (intervention-id uint))
  (let
    (
      (intervention-data (unwrap! (map-get? interventions { intervention-id: intervention-id }) err-not-found))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get is-completed intervention-data)) err-invalid-status)
    
    (map-set interventions
      { intervention-id: intervention-id }
      (merge intervention-data {
        is-completed: true,
        completion-date: (some block-height)
      })
    )
    (ok true)
  )
)

;; Update compliance target
(define-public (update-compliance-target (new-target uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-target u100) err-invalid-input)
    
    (var-set facility-compliance-target new-target)
    (ok true)
  )
)

;; Deactivate healthcare worker
(define-public (deactivate-worker (worker-id principal))
  (let
    (
      (worker-data (unwrap! (map-get? healthcare-workers { worker-id: worker-id }) err-not-found))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set healthcare-workers
      { worker-id: worker-id }
      (merge worker-data { is-active: false })
    )
    (ok true)
  )
)

