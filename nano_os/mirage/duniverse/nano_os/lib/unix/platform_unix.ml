open Nano_os

module Block = File_disk
module Net = Socket_net
module Clock = Clock_unix
module Random = Random_unix

module _ : App.PLATFORM
  with module Block = Block
   and module Net = Net
   and module Clock = Clock
   and module Random = Random =
struct
  module Block = Block
  module Net = Net
  module Clock = Clock
  module Random = Random
end
