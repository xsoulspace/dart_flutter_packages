// ignore_for_file: lines_longer_than_80_chars, unsafe_variance

/// {@template chain_then_record}
/// Represents the result of a chain command execution, containing the next command type and result value.
///
/// This record encapsulates the output of a chain command, specifying which command should
/// execute next and what result was produced. When [type] is `null`, the chain execution terminates.
///
/// Used as the primary data structure for communication between chain commands in [Chain].
///
/// ```dart
/// // Example of creating a ChainThenRecord
/// final record = (type: NextCommand(), result: 'Step completed successfully');
///
/// // Example of terminating a chain
/// final finalRecord = (type: null, result: 'All steps completed');
/// ```
///
/// @ai Use this record type to pass data between chain commands.
/// Set [type] to `null` to terminate chain execution.
/// {@endtemplate}
typedef ChainThenRecord<TResult> = ({ChainCommand? type, TResult result});

/// {@template chain_command_exe}
/// Function signature for executing a single step in a command chain.
///
/// This typedef defines the contract for chain command functions. Each command receives
/// the current [ChainThenRecord] from the previous step and returns a new [ChainThenRecord]
/// specifying the next command to execute and its result.
///
/// The function is asynchronous to support operations like network calls, file I/O,
/// or other time-consuming tasks within the chain.
///
/// ```dart
/// // Example implementation
/// Future<ChainThenRecord<String>> validateUser(ChainThenRecord<String> input) async {
///   final isValid = await validateUserData(input.result);
///   return (
///     type: isValid ? ProcessUserData() : HandleValidationError(),
///     result: isValid ? 'User validated' : 'Validation failed'
///   );
/// }
/// ```
///
/// @ai Implement this typedef for each step in your command chain.
/// Return a new [ChainThenRecord] to continue the chain or set type to null to terminate.
/// {@endtemplate}
typedef ChainCommandExe<TThenResult> =
    Future<ChainThenRecord<TThenResult>> Function(ChainThenRecord<TThenResult>);

/// {@template chain_commands}
/// A registry mapping command types to their execution functions.
///
/// This typedef defines a lookup table that associates each [ChainCommand] type with
/// its corresponding [ChainCommandExe] function. The [Chain] class uses this mapping
/// to determine which function to execute for each step in the command chain.
///
/// ```dart
/// // Example of creating a command registry
/// final commands = <ChainCommand, ChainCommandExe<String>>{
///   ValidateUser(): (record) async => (type: ProcessData(), result: 'validated'),
///   ProcessData(): (record) async => (type: SaveResult(), result: 'processed'),
///   SaveResult(): (record) async => (type: null, result: 'completed'),
/// };
/// ```
///
/// @ai Use this typedef to register all possible command steps.
/// Ensure each [ChainCommand] type has a corresponding execution function.
/// {@endtemplate}
typedef ChainCommands<TThenResult> =
    Map<ChainCommand, ChainCommandExe<TThenResult>>;

/// {@template chain}
/// A generic command chain executor that enables dynamic, type-driven asynchronous command pipelines.
///
/// This class provides a powerful pattern for building complex workflows where each step
/// can dynamically determine the next step to execute based on its results. Commands are
/// executed sequentially, with each command receiving the result from the previous command
/// and returning instructions for what to do next.
///
/// The chain execution follows this pattern:
/// 1. Start with an initial function that produces the first [ChainThenRecord]
/// 2. Execute each command in sequence based on the [type] specified in the record
/// 3. Continue until a command returns a [type] of `null`, terminating the chain
///
/// ## Key Features
/// - **Type-driven execution**: Commands determine their successors dynamically
/// - **Async support**: All commands are asynchronous, supporting I/O operations
/// - **Flexible workflows**: Easy to add, remove, or reorder steps
/// - **Error handling**: Each step can handle errors and route to appropriate handlers
///
/// ## Example Usage
/// ```dart
/// // Define command types
/// class ValidateInput extends ChainCommand {}
/// class ProcessData extends ChainCommand {}
/// class SaveResult extends ChainCommand {}
/// class HandleError extends ChainCommand {}
///
/// // Create the chain
/// final dataProcessingChain = Chain<Map<String, dynamic>, String>(
///   startWith: (input) async {
///     final isValid = input.containsKey('data');
///     return (
///       type: isValid ? ValidateInput() : HandleError(),
///       result: isValid ? 'Input validated' : 'Missing data field'
///     );
///   },
///   then: {
///     ValidateInput(): (record) async {
///       // Perform validation logic
///       final isValidData = await validateData(record.result);
///       return (
///         type: isValidData ? ProcessData() : HandleError(),
///         result: isValidData ? 'Data validated successfully' : 'Validation failed'
///       );
///     },
///     ProcessData(): (record) async {
///       // Process the validated data
///       final result = await processValidatedData(record.result);
///       return (
///         type: SaveResult(),
///         result: result
///       );
///     },
///     SaveResult(): (record) async {
///       // Save the processing result
///       await saveToDatabase(record.result);
///       return (
///         type: null, // Terminate the chain
///         result: 'Processing completed successfully'
///       );
///     },
///     HandleError(): (record) async {
///       // Handle any errors that occurred
///       await logError(record.result);
///       return (
///         type: null, // Terminate the chain
///         result: 'Error handled: ${record.result}'
///       );
///     },
///   },
/// );
///
/// // Execute the chain
/// final result = await dataProcessingChain({'data': 'some input'});
/// ```
///
/// ## Use Cases
/// - **Data processing pipelines**: Validate → Transform → Store
/// - **API request chains**: Authenticate → Request → Parse → Cache
/// - **Business workflows**: Validate → Process → Notify → Audit
/// - **Error recovery**: Try → Fallback → Retry → Report
///
/// @ai Use [Chain] to build extensible, type-driven async command pipelines.
/// Each step can determine the next step dynamically based on its results.
/// Ideal for complex workflows where execution flow depends on intermediate results.
/// {@endtemplate}
class Chain<TStartWith, TThenResult> {
  /// {@template chain_constructor}
  /// Creates a new command chain with the specified entry point and command registry.
  ///
  /// [startWith] - The initial function that starts the chain execution.
  /// This function receives an argument of type [TStartWith] and produces the first [ChainThenRecord].
  ///
  /// [then] - A registry of all possible commands that can be executed in this chain.
  /// Each [ChainCommand] type must have a corresponding [ChainCommandExe] function.
  ///
  /// @ai Ensure all [ChainCommand] types referenced in the chain have corresponding entries in the [then] map.
  /// {@endtemplate}
  Chain({
    required this.startWith,
    required final ChainCommands<TThenResult> then,
  }) : _commands = then;

  /// {@template chain_start_with}
  /// The entry point function that initiates chain execution.
  ///
  /// This function takes an argument of type [TStartWith] and returns the initial
  /// [ChainThenRecord] that specifies which command should execute first and
  /// provides the initial result data.
  ///
  /// @ai Implement this function to set up the initial state and determine the first command to execute.
  /// {@endtemplate}
  final Future<ChainThenRecord<TThenResult>> Function(TStartWith arg) startWith;

  /// {@template chain_commands_private}
  /// Internal registry of available chain commands.
  ///
  /// This map associates each [ChainCommand] type with its execution function.
  /// The chain executor uses this registry to look up commands during execution.
  ///
  /// @ai This is intentionally private to prevent external modification of the command registry.
  /// {@endtemplate}
  final ChainCommands<TThenResult> _commands;

  /// {@template chain_call}
  /// Executes the command chain starting with the provided argument.
  ///
  /// This method initiates the chain execution by calling [startWith] with the given [arg],
  /// then continues executing commands in sequence based on the [type] specified in each
  /// [ChainThenRecord]. The chain terminates when a command returns a [type] of `null`.
  ///
  /// The execution includes a safety mechanism that prevents infinite loops by limiting
  /// the number of iterations to the number of registered commands.
  ///
  /// @ai Call this method to start the chain execution. The method completes when the chain terminates.
  /// {@endtemplate}
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

/// {@template chain_command}
/// A marker interface that identifies classes as executable commands in a command chain.
///
/// This interface serves as a type-safe way to define command types that can be used
/// in [ChainCommands] registries. By implementing this interface, a class becomes
/// eligible to be used as a command type in chain execution.
///
/// ## Usage Pattern
/// ```dart
/// // Define specific command types
/// class ValidateUser extends ChainCommand {}
/// class ProcessPayment extends ChainCommand {}
/// class SendNotification extends ChainCommand {}
/// class LogActivity extends ChainCommand {}
///
/// // Use in chain commands registry
/// final commands = <ChainCommand, ChainCommandExe<String>>{
///   ValidateUser(): (record) async => (type: ProcessPayment(), result: 'validated'),
///   ProcessPayment(): (record) async => (type: SendNotification(), result: 'paid'),
///   SendNotification(): (record) async => (type: LogActivity(), result: 'notified'),
///   LogActivity(): (record) async => (type: null, result: 'completed'),
/// };
/// ```
///
/// ## Best Practices
/// - Create specific command classes for each distinct step in your workflow
/// - Use descriptive names that clearly indicate the command's purpose
/// - Keep command classes simple with no additional properties or methods
/// - Consider grouping related commands in a single file or module
///
/// @ai Use this interface to define command types for your chain workflows.
/// Each command type should represent a distinct step or decision point in your process.
/// {@endtemplate}
interface class ChainCommand {}
