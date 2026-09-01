let () =
  let w = 0x80000000l in
  Printf.printf "%%08lx: %08lx\n" w;
  let w2 = 0xe3b0c442l in
  Printf.printf "%%08lx: %08lx\n" w2
