------------------------- MODULE PayoutRecovery -------------------------
EXTENDS Naturals

VARIABLES local, provider, hold, journals, requests, accepted, funded
vars == <<local, provider, hold, journals, requests, accepted, funded>>

Init == /\ local = "idle" /\ provider = "absent" /\ hold = FALSE
        /\ journals = 0 /\ requests = 0 /\ accepted = FALSE /\ funded = FALSE

Accept == /\ ~accepted /\ accepted' = TRUE
          /\ UNCHANGED <<local, provider, hold, journals, requests, funded>>
Fund == /\ ~funded /\ funded' = TRUE
        /\ UNCHANGED <<local, provider, hold, journals, requests, accepted>>
Request == /\ local = "idle" /\ accepted /\ funded /\ ~hold
           /\ local' = "requested"
           /\ UNCHANGED <<provider, hold, journals, requests, accepted, funded>>
Hold == /\ local \in {"idle", "requested"} /\ ~hold /\ hold' = TRUE
        /\ UNCHANGED <<local, provider, journals, requests, accepted, funded>>
Release == /\ hold /\ hold' = FALSE
           /\ UNCHANGED <<local, provider, journals, requests, accepted, funded>>
Claim == /\ local = "requested" /\ ~hold /\ local' = "dispatching"
         /\ UNCHANGED <<provider, hold, journals, requests, accepted, funded>>
Execute == /\ local = "dispatching" /\ requests < 2
           /\ provider' = "confirmed" /\ requests' = requests + 1
           /\ UNCHANGED <<local, hold, journals, accepted, funded>>
Timeout == /\ local = "dispatching" /\ local' = "unknown"
           /\ UNCHANGED <<provider, hold, journals, requests, accepted, funded>>
Retry == /\ local = "unknown" /\ provider = "absent" /\ local' = "dispatching"
         /\ UNCHANGED <<provider, hold, journals, requests, accepted, funded>>
Observe == /\ local \in {"dispatching", "unknown"} /\ provider = "confirmed"
           /\ local' = "confirmed" /\ journals' = 1
           /\ UNCHANGED <<provider, hold, requests, accepted, funded>>
Duplicate == /\ local = "confirmed" /\ UNCHANGED vars

Next == Accept \/ Fund \/ Request \/ Hold \/ Release \/ Claim \/ Execute \/ Timeout \/ Retry \/ Observe \/ Duplicate
Spec == Init /\ [][Next]_vars
TypeOK == /\ local \in {"idle", "requested", "dispatching", "unknown", "confirmed"}
          /\ provider \in {"absent", "confirmed"} /\ journals \in 0..1 /\ requests \in 0..2
          /\ hold \in BOOLEAN /\ accepted \in BOOLEAN /\ funded \in BOOLEAN
NoPayoutUnderHold == local \in {"dispatching", "unknown", "confirmed"} => ~hold
NeedsAcceptanceAndFunding == local # "idle" => accepted /\ funded
AccountingMatchesConfirmation == (local = "confirmed") <=> (journals = 1)
ConfirmedExistsAtProvider == local = "confirmed" => provider = "confirmed"
=============================================================================
