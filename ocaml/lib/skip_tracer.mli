(**
   skip_tracer.mli - Interfaces with third-party skip tracing APIs (e.g., BatchSkipTracing)
   to append real homeowner phone numbers to leads.
*)

val is_synthesized_name : string -> bool

val build_payload : Types.raw_lead -> string

val extract_phone_number : string -> string option

val append_phone_number : ?api_url:string -> Types.raw_lead -> (Types.raw_lead, string) result
