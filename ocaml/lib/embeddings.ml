(**
   embeddings.ml - Deterministic 256-D Offline Feature Hashing Embedder.
   Uses multi-scale signed feature hashing with subword n-grams and domain token boosting.
   100% offline, zero external models, zero cloud APIs, zero mock dependencies.
*)

let default_dimension = 256

(** Precomputed IEEE 802.3 CRC32 lookup table (polynomial 0xEDB88320). *)
let crc32_table =
  let poly = 0xEDB88320 in
  Array.init 256 (fun i ->
    let crc = ref i in
    for _ = 0 to 7 do
      if (!crc land 1) <> 0 then
        crc := ((!crc lsr 1) lxor poly) land 0xFFFFFFFF
      else
        crc := (!crc lsr 1) land 0xFFFFFFFF
    done;
    !crc
  )

let crc32 (s : string) : int =
  let crc = ref 0xFFFFFFFF in
  for i = 0 to String.length s - 1 do
    let b = Char.code s.[i] in
    let idx = (!crc lxor b) land 0xFF in
    crc := ((!crc lsr 8) lxor crc32_table.(idx)) land 0xFFFFFFFF
  done;
  (!crc lxor 0xFFFFFFFF) land 0xFFFFFFFF

let sign_of_token (s : string) : float =
  let digest = Digest.string s in
  if (Char.code digest.[0]) land 1 = 0 then 1.0 else -1.0

let is_word_boundary_char (c : char) : bool =
  not ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_')

let is_token_char (c : char) : bool =
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
  c = '_' || c = '-' || c = '.' || c = ':' || c = '#' ||
  c = '[' || c = ']' || c = '=' || c = '"'

let tokenize (text : string) : (string * float) list =
  let trimmed = String.trim text in
  if String.length trimmed = 0 then
    [("__EMPTY__", 1.0)]
  else
    let cleaned = String.lowercase_ascii trimmed in
    let len = String.length cleaned in

    (* 1. Extract status codes (4xx and 5xx) *)
    let status_tokens = ref [] in
    for i = 0 to len - 3 do
      let c0 = cleaned.[i] in
      let c1 = cleaned.[i + 1] in
      let c2 = cleaned.[i + 2] in
      let is_status_start = (c0 = '4' || c0 = '5') &&
                            (c1 >= '0' && c1 <= '9') &&
                            (c2 >= '0' && c2 <= '9') in
      if is_status_start then
        let left_bound = (i = 0 || is_word_boundary_char cleaned.[i - 1]) in
        let right_bound = (i + 3 = len || is_word_boundary_char cleaned.[i + 3]) in
        if left_bound && right_bound then
          let code = String.sub cleaned i 3 in
          status_tokens := ("status:" ^ code, 3.0) :: !status_tokens
    done;
    let status_tokens = List.rev !status_tokens in

    (* 2. Extract lexical words and domain components *)
    let words = ref [] in
    let i = ref 0 in
    while !i < len do
      while !i < len && not (is_token_char cleaned.[!i]) do
        incr i
      done;
      let start_pos = !i in
      while !i < len && is_token_char cleaned.[!i] do
        incr i
      done;
      if !i > start_pos then
        let w = String.sub cleaned start_pos (!i - start_pos) in
        words := w :: !words
    done;
    let word_list = List.rev !words in
    let word_tokens = List.map (fun w -> ("w:" ^ w, 1.5)) word_list in

    (* 3. Extract word bigrams *)
    let bigram_tokens = ref [] in
    let rec make_bigrams = function
      | w1 :: (w2 :: _ as rest) ->
          bigram_tokens := ("bi:" ^ w1 ^ "_" ^ w2, 2.0) :: !bigram_tokens;
          make_bigrams rest
      | _ -> ()
    in
    make_bigrams word_list;
    let bigram_tokens = List.rev !bigram_tokens in

    (* 4. Extract character 3-grams and 4-grams *)
    let ngram_tokens = ref [] in
    List.iter (fun w ->
      let w_len = String.length w in
      if w_len >= 3 then
        for j = 0 to w_len - 3 do
          ngram_tokens := ("3g:" ^ String.sub w j 3, 0.5) :: !ngram_tokens
        done;
      if w_len >= 4 then
        for j = 0 to w_len - 4 do
          ngram_tokens := ("4g:" ^ String.sub w j 4, 0.5) :: !ngram_tokens
        done
    ) word_list;
    let ngram_tokens = List.rev !ngram_tokens in

    status_tokens @ word_tokens @ bigram_tokens @ ngram_tokens

let l2_norm (vec : float array) : float =
  let sum = ref 0.0 in
  for i = 0 to Array.length vec - 1 do
    sum := !sum +. (vec.(i) *. vec.(i))
  done;
  sqrt !sum

let embed_text ?(dimension = default_dimension) (text : string) : float array =
  if dimension <= 0 then invalid_arg "Embedding dimension must be positive";
  let vec = Array.make dimension 0.0 in
  let tokens = tokenize text in
  List.iter (fun (tok, weight) ->
    let c = crc32 tok in
    let idx = c mod dimension in
    let sign = sign_of_token tok in
    vec.(idx) <- vec.(idx) +. (sign *. weight)
  ) tokens;
  let norm = l2_norm vec in
  if norm > 1e-12 then
    Array.map (fun x -> x /. norm) vec
  else (
    let out = Array.make dimension 0.0 in
    out.(0) <- 1.0;
    out
  )

let embed_batch ?(dimension = default_dimension) (texts : string list) : float array list =
  List.map (embed_text ~dimension) texts

let cosine_similarity (v1 : float array) (v2 : float array) : float =
  let len1 = Array.length v1 in
  let len2 = Array.length v2 in
  if len1 = 0 || len1 <> len2 then 0.0
  else
    let n1 = l2_norm v1 in
    let n2 = l2_norm v2 in
    if n1 <= 1e-12 || n2 <= 1e-12 then 0.0
    else
      let dot = ref 0.0 in
      for i = 0 to len1 - 1 do
        dot := !dot +. (v1.(i) *. v2.(i))
      done;
      let sim = !dot /. (n1 *. n2) in
      if sim > 1.0 then 1.0
      else if sim < -1.0 then -1.0
      else sim

let batch_cosine_similarity (q : float array) (docs : float array list) : float list =
  List.map (fun doc -> cosine_similarity q doc) docs
