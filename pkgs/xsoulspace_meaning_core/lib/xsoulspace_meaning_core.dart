/// Portable contracts. Execution, authority and recovery remain with hosts.
library;

export 'package:intentcall_schema/intentcall_schema.dart'
    show
        InputSchema,
        AgentArguments,
        AgentValidationException,
        validateAgainstSchema;
export 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show
        EditExecutableWire,
        EditExecutableKind,
        EditVerification,
        MeaningTreeExport;
export 'src/meaning_contracts.dart';
export 'src/meaning_read_contract.dart';
