import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/effect_parameter_refinement.dart';

void main() {
  test(
    'new plugin scales around actual initial value, including negative dB',
    () {
      expect(
        applyDeferredParameterRefinement(
          current: -12,
          proposal: -24,
          parameter: {'type': 'float', 'min': -60, 'max': 0, 'interval': 0.1},
          action: {'refinement_scale': 0.5},
        ),
        -18,
      );
      expect(
        applyDeferredParameterRefinement(
          current: 1000,
          proposal: 3000,
          parameter: {'type': 'float', 'min': 20, 'max': 20000},
          action: {'refinement_scale': 0.5},
        ),
        2000,
      );
    },
  );
  test('deferred values respect engine range, interval and scalar bounds', () {
    expect(
      applyDeferredParameterRefinement(
        current: 0.2,
        proposal: 0.8,
        parameter: {'type': 'float', 'min': 0, 'max': 1, 'interval': 0.1},
        action: {'refinement_scale': 20},
      ),
      1,
    );
    expect(
      applyDeferredParameterRefinement(
        current: 0.2,
        proposal: 0.8,
        parameter: {'type': 'float', 'min': 0, 'max': 1, 'interval': 0.1},
        action: {'refinement_scale': 0.24},
      ),
      closeTo(0.3, 1e-9),
    );
  });
  test(
    'legacy actions and discrete or invalid metadata retain their proposal',
    () {
      for (final type in ['float', 'bool', 'choice']) {
        expect(
          applyDeferredParameterRefinement(
            current: 0,
            proposal: 1,
            parameter: {'type': type, 'min': 0, 'max': 1},
            action: {},
          ),
          1,
        );
      }
      for (final type in ['bool', 'choice']) {
        expect(
          applyDeferredParameterRefinement(
            current: 0,
            proposal: 1,
            parameter: {'type': type, 'min': 0, 'max': 1},
            action: {'refinement_scale': 0.1},
          ),
          1,
        );
      }
      expect(
        applyDeferredParameterRefinement(
          current: 0,
          proposal: 1,
          parameter: {'type': 'float', 'min': 0, 'max': 1},
          action: {'refinement_scale': double.nan},
        ),
        1,
      );
    },
  );
}
