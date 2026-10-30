/// The generations, run on aityx from the app itself: the board's state
/// (lib/aityx/life.dart) with the Life model (assets/models/life.json)
/// POSTed to aityx's /v1/systemone through aityx_web, on the user's key
/// or the index server's dev proxy. What the former API did, with its
/// checks and its wording.
library;

import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart';

import '../life/board.dart';
import '../life/generation.dart';
import 'life.dart';

/// Where the Life model is, among the app's assets.
const lifeModelAsset = 'assets/models/life.json';

/// The Life model, read from the app's assets.
Future<Map<String, Object?>> loadLifeModel([AssetBundle? bundle]) async =>
    jsonDecode(await (bundle ?? rootBundle).loadString(lifeModelAsset))
        as Map<String, Object?>;

/// Runs each generation on aityx: one systemone call per generation.
class AityxGenerationStepper implements GenerationStepper {
  /// [aityx] makes the calls (a new AityxClient, which finds the key,
  /// unless a test gives one); [model] reads the Life model (the app's
  /// asset unless a test gives its own).
  AityxGenerationStepper({
    AityxClient? aityx,
    Future<Map<String, Object?>> Function()? model,
    this.deadline = const Duration(seconds: 30),
  }) : _aityx = aityx ?? AityxClient(),
       _readModel = model ?? loadLifeModel;

  final AityxClient _aityx;
  final Future<Map<String, Object?>> Function() _readModel;

  /// How long a generation waits for aityx's whole answer.
  final Duration deadline;

  /// Read on the first generation, and kept once it loads; read again on
  /// the next generation if it didn't.
  Future<Map<String, Object?>>? _model;

  Future<Map<String, Object?>> _lifeModel() async {
    final reading = _model ??= _readModel();
    try {
      return await reading;
    } catch (_) {
      if (identical(_model, reading)) _model = null;
      throw _failed('the Life model did not load');
    }
  }

  /// Throws [GenerationException] with a message for the user.
  @override
  Future<GenerationOutcome> step(
    int generation,
    Map<String, bool> rules,
    Map<SituationKey, List<Cell>> situations,
    List<Cluster> clusters,
  ) async {
    final Map<String, Object?> state;
    try {
      state = stateFrom(
        generationBody(generation, rules, situations, clusters),
      );
    } on InvalidRequest catch (error) {
      throw _failed('$error');
    }
    final sent = generationRequest(await _lifeModel(), state);
    final AityxAnswer answer;
    try {
      answer = await _aityx.systemone(sent, timeout: deadline);
    } on AityxNoKey {
      throw const GenerationException('${AityxNoKey.message}.', noKey: true);
    } on AityxUnreachable catch (error) {
      // The former API's wording for its deadline.
      final late = error.cause?.startsWith('timed out') ?? false;
      throw _failed('${AityxUnreachable.message}${late ? ' in time' : ''}');
    }
    if (!answer.ok) throw _failed(answer.problem!);
    final json = answer.json;
    if (json is! Map) throw _failed('unexpected answer from aityx');
    final response = json.cast<String, Object?>();
    final Map<String, Object?> decided;
    try {
      decided = toGeneration(sent, response);
    } on GenerationFailed catch (error) {
      throw _failed('aityx could not decide it: $error');
    } catch (_) {
      // A field of another type than the model's (a TypeError): the
      // former API answered 500 for it; the screen only knows
      // GenerationException.
      throw _failed('unexpected answer from aityx');
    }
    // The user's key, to keep it out of the panel; none in dev mode.
    final key = (await _aityx.connection()).key ?? '';
    try {
      return GenerationOutcome.fromJson(
        withAityx(
          decided,
          sent,
          response,
          answer.text,
          key,
          tookMs: answer.took.inMilliseconds,
        ),
      );
    } catch (_) {
      throw const GenerationException('aityx answered without a generation.');
    }
  }

  static GenerationException _failed(String why) =>
      GenerationException('Could not run the generation: $why.');
}
