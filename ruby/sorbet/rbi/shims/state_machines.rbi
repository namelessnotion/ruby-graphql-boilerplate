# typed: true

# `bin/tapioca gem state_machines` reflects `state_machine`/`event` as plain
# `def foo(*args, &blk); end` stubs (no `sig`), because the gem itself carries
# no Sorbet signatures. That's enough to silence "method does not exist", but
# the block passed to each is `instance_eval`'d by the gem (see
# `StateMachines::Machine::ClassMethods#find_or_create` and
# `StateMachines::Machine::EventMethods#event`), so its `self` is the
# `Machine`/`Event`, not the enclosing class — something only a hand-written
# `T.proc.bind` sig can express. Hence a shim rather than gem/DSL output.
module StateMachines
  module MacroMethods
    sig { params(args: T.untyped, blk: T.nilable(T.proc.bind(StateMachines::Machine).void)).returns(StateMachines::Machine) }
    def state_machine(*args, &blk); end
  end

  class Machine
    sig { params(names: T.untyped, blk: T.nilable(T.proc.bind(StateMachines::Event).void)).returns(T.untyped) }
    def event(*names, &blk); end
  end
end
