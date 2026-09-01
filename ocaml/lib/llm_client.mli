(**
   llm_client.mli - Local LLM Inference Client and Response Cleansing Engine.
   Features:
     - Pure OCaml HTTP client targeting local OpenAI-compatible inference endpoints (localhost:8000/v1).
     - OpenAI chat completion JSON payload formatting with system prompts.
     - Response cleansing: strips thinking tags (<think>...</think>), markdown code fences,
       and isolates balanced-brace JSON payloads.
     - Structured decoding into property and permit extraction records.
*)

type config = {
  base_url : string;
  model : string;
  api_key : string;
  timeout : float;
}

val default_config : config

type property_extraction = {
  address : string;
  zip_code : string;
  property_type : string;
  roof_type : string;
  is_hoa : bool;
  is_rental : bool;
  estimated_value : float option;
  bedrooms : int option;
  bathrooms : float option;
  sqft : int option;
  year_built : int option;
  description : string option;
  confidence_score : float;
}

type county_permit_extraction = {
  address : string;
  apn : string option;
  owner_name : string option;
  assessed_value : float option;
  last_roof_permit_date : string option;
  permit_history : Types.permit_record list;
  roof_age_years : float option;
  is_hoa : bool;
  is_rental : bool;
  confidence_score : float;
}

val clean_json_response : string -> string
(** [clean_json_response text] removes <think> / <thought> tags, strips markdown code fences,
    and extracts the balanced-brace JSON object substring. *)

val format_chat_payload : ?config:config -> system_prompt:string -> user_content:string -> unit -> string
(** [format_chat_payload ?config ~system_prompt ~user_content ()] builds an OpenAI-compatible
    chat completions JSON request body with temperature 0.0 and json_object response format. *)

val parse_property_extraction : string -> (property_extraction, string) result
(** [parse_property_extraction json_str] decodes a JSON string into a [property_extraction]. *)

val parse_county_permit_extraction : string -> (county_permit_extraction, string) result
(** [parse_county_permit_extraction json_str] decodes a JSON string into a [county_permit_extraction]. *)

val extract_property_details :
  ?config:config ->
  string ->
  (property_extraction, string) result
(** [extract_property_details ?config html_or_text] sends extraction request to local LLM
    and parses structured property details. *)

val extract_county_permit_details :
  ?config:config ->
  string ->
  (county_permit_extraction, string) result
(** [extract_county_permit_details ?config html_or_text] sends extraction request to local LLM
    and parses structured county/permit details. *)
