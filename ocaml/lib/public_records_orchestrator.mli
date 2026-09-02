(**
   public_records_orchestrator.mli - Unified public records acquisition orchestrator.
   Orchestrates 5 public records microservices:
     1. Homeowner Names (Assessor Secured Roll wv5m-vpq2 & Deed Registry)
     2. Homeowner Addresses (Assessor Roll & Enterprise Addressing System)
     3. GIS Roofs (Building Footprints sfnk-6tdn & SF Planning PIM)
     4. Roof Permits (DBI Building Permits i98e-djp9 & PTS)
     5. Property Tax Records (Assessor Roll & Treasurer Tax Collector)
*)

open Types

type public_records_answers = {
  names_source : string;
  addresses_source : string;
  gis_source : string;
  permits_source : string;
  tax_source : string;
}

val get_public_records_answers : unit -> public_records_answers
(** [get_public_records_answers ()] returns the public records data source answers for all 5 municipal questions. *)

val acquire_neighborhood_public_records :
  ?limit:int ->
  ?timeout:float ->
  neighborhood:string ->
  unit ->
  (verified_lead list, string) result
(** [acquire_neighborhood_public_records ?limit ?timeout ~neighborhood ()]
    queries all 5 municipal microservices, correlates data across public records,
    and returns qualified leads with cryptographic proofs. *)
