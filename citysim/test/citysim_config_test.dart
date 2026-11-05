import 'package:citysim/config/citysim_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson reads every field, including serverUrl', () {
    final config = CitysimConfig.fromJson(const {
      'dataSource': 'csv',
      'spreadsheetId': '',
      'serverUrl': 'http://localhost:9200',
    });
    expect(config.dataSource, CitysimDataSource.csv);
    expect(config.spreadsheetId, '');
    expect(config.serverUrl, 'http://localhost:9200');
  });

  test('fromJson defaults spreadsheetId and serverUrl when absent', () {
    final config = CitysimConfig.fromJson(const {'dataSource': 'sheets'});
    expect(config.dataSource, CitysimDataSource.sheets);
    expect(config.spreadsheetId, '');
    expect(config.serverUrl, '');
  });
}
