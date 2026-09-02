(**
   skip_tracer.mli - Interfaces with third-party skip tracing APIs (e.g., BatchSkipTracing)
   to append real homeowner phone numbers to leads.
*)

(** 
   Appends a real phone number to a raw lead by querying a skip tracing API.
   Requires the environment variable SKIP_TRACING_API_KEY to be set.
   If the API key is not set, or the API call fails, the lead is returned unmodified or with an error.
*)
val append_phone_number : Types.raw_lead -> (Types.raw_lead, string) result
