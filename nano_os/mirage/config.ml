open Mirage

let packages = [
  package "nano_os";
  package "duration";
  package "mirage-sleep";
]

let main =
  main
    ~packages
    "Unikernel.Main"
    (block @-> network @-> mtime @-> job)

let () =
  register
    "nano_os"
    [ main
      $ block_of_file "nanodisk"
      $ default_network
      $ default_mtime
    ]
