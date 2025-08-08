// ignore_for_file: lines_longer_than_80_chars, unsafe_variance
/// {@template chain_then_record}
/// Represents the result of a chain command, including the next [type] to execute and the [result] value.
///
/// Used as the data structure passed between chain commands in [Chain].
///
/// @ai Use this typedef to encapsulate both the result and the next command type in a chain.
/// {@endtemplate}
typedef ChainThenRecord<TResult> = ({ChainCommand? type, TResult result});

/// {@template chain_command_exe}
/// Signature for a chain command function that takes a [ChainThenRecord] and returns a [Future] of the next [ChainThenRecord].
///
/// Used in [ChainCommands] to define the steps in a command chain.
///
/// @ai Implement this typedef for each step in a command chain.
/// {@endtemplate}
typedef ChainCommandExe<TThenResult> =
    Future<ChainThenRecord<TThenResult>> Function(ChainThenRecord<TThenResult>);

/// {@template chain_commands}
/// A map of [ChainCommand] to [ChainCommandExe], representing the available steps in a command chain.
///
/// Used by [Chain] to look up and execute the next command based on the [type] in [ChainThenRecord].
///
/// @ai Use this typedef to register all possible chain steps.
/// {@endtemplate}
typedef ChainCommands<TThenResult> =
    Map<ChainCommand, ChainCommandExe<TThenResult>>;

/// {@template chain}
/// A generic command chain executor that allows chaining asynchronous commands based on dynamic types.
///
/// This class enables a flexible, type-driven command pipeline. Each command returns a [ChainThenRecord]
/// indicating the next command type to execute. The chain continues until a command returns a [type] of `null`.
///
/// ## Example
/// ```dart
/// final chain = Chain<StartArg, ResultType>(
///   startWith: (arg) async => (type: FirstCommandType, result: initialResult),
///   then: {
///     FirstCommandType: (record) async => (type: SecondCommandType, result: ...),
///     SecondCommandType: (record) async => (type: null, result: ...),
///   },
/// );
/// await chain(startArg);
/// ```
///
/// @ai Use [Chain] to build extensible, type-driven async command pipelines. Each step can determine the next step dynamically.
/// {@endtemplate}
class Chain<TStartWith, TThenResult> {
  /// {@macro chain}
  ///
  /// [startWith] is the entry point function, producing the initial [ChainThenRecord].
  /// [then] is a map of command types to their corresponding [ChainCommandExe]s.
  Chain({
    required this.startWith,
    required final ChainCommands<TThenResult> then,
  }) : _commands = then;

  /// The entry point function for the chain.
  ///
  /// Takes an argument of type [TStartWith] and returns a [Future] of [ChainThenRecord].
  ///
  /// @ai Implement this to produce the initial chain record and type.
  final Future<ChainThenRecord<TThenResult>> Function(TStartWith arg) startWith;

  /// The map of available chain commands, keyed by [Type].
  ///
  /// @ai Register all possible chain steps here.
  final ChainCommands<TThenResult> _commands;

  /// Executes the chain starting with [arg].
  ///
  /// The chain continues as long as the returned [type] from each command is not `null`.
  ///
  /// @ai Call this method to start the chain. Each command can determine the next step.
  Future<void> call(final TStartWith arg) async {
    final result = await startWith(arg);
    if (result.type == null) return;
    ChainThenRecord<TThenResult> currentResult = result;
    var type = currentResult.type;
    var i = 0;
    while (type != null && i < _commands.length) {
      i++;
      final command = _commands[type];
      if (command == null) return;
      currentResult = await command(currentResult);
      type = currentResult.type;
    }
  }
}

/// {@template chain_command_interface}
/// A marker interface for chain commands.
///
/// @ai Use this interface to define the types of commands that can be executed in a chain.
/// {@endtemplate}
interface class ChainCommand {}
