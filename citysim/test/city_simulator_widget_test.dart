import 'dart:ui' show Size;

import 'package:citysim/city_simulator_app.dart';
import 'package:citysim/data/city_save_store.dart';
import 'package:citysim/domain/city_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCitySaveStore implements CitySaveStore {
  CityState? state;

  @override
  Future<void> clear() async => state = null;

  @override
  Future<CityState?> load() async => state;

  @override
  Future<void> save(CityState state) async => this.state = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile preview loads and check-in is once per displayed date', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryCitySaveStore();

    await tester.pumpWidget(CitySimulatorApp(saveStore: store));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('A place that grows with you'), findsOneWidget);
    expect(find.text('Check in · +1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Check in · +1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Checked in'), findsOneWidget);
    expect(store.state?.coins, 1);
    expect(tester.takeException(), isNull);
  });
}
