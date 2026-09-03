(**
   phone_validator.mli - North American Numbering Plan (NANP) phone validation,
   dummy number rejection, area code classification, and canonical formatting.
*)

type area_code_tier =
  | SF_Primary
  | Bay_Area
  | Valid_US
  | Invalid_Area

type validation_error =
  | EmptyNumber
  | InvalidLength of int
  | InvalidCountryCode of string
  | InvalidNpaStartDigit of char
  | InvalidNxxStartDigit of char
  | ReservedN11Code of string
  | TollFreeAreaCode of string
  | PremiumAreaCode of string
  | Fictitious555Number of string
  | InvalidPrefix000or111 of string
  | RepeatingDigits of string
  | SequentialDigits of string
  | InvalidAreaCode of string
  | MaliciousFormulaPrefix of string

type validated_phone = {
  raw : string;
  digits : string;
  npa : string;
  nxx : string;
  station : string;
  canonical : string;
  tier : area_code_tier;
}

val is_valid_npa : string -> bool

val get_area_code_tier : string -> area_code_tier

val is_dummy_number : string -> bool

val sanitize_and_normalize : string -> (validated_phone, validation_error) result

val format_canonical : validated_phone -> string

val extract_valid_phones_from_text : string -> validated_phone list

val is_valid_phone : string -> bool

val normalize_to_canonical : string -> string option
