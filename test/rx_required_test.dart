import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/models/models.dart';

void main() {
  test('처방 필요 여부: rx_required 우선, 없으면 etc_otc, 모르면 null', () {
    expect(rxRequiredFrom({'rx_required': true}), isTrue);
    expect(rxRequiredFrom({'rx_required': false, 'etc_otc': '전문의약품'}), isFalse);
    expect(rxRequiredFrom({'etc_otc': '전문의약품'}), isTrue);
    expect(rxRequiredFrom({'etc_otc': '일반의약품'}), isFalse);
    expect(rxRequiredFrom({'etc_otc': null}), isNull);
    expect(rxRequiredFrom({}), isNull);
  });

  test('검색 결과·내 약에 처방 표시 값이 들어온다 (직접 추가는 항상 null)', () {
    final s = DrugSummary.fromJson(
        {'item_seq': '1', 'item_name': '타이레놀정500밀리그람', 'etc_otc': '일반의약품', 'rx_required': false});
    expect((s.etcOtc, s.rxRequired), ('일반의약품', false));
    final d = DrugDetail.fromJson({'item_seq': '2', 'item_name': '어떤약', 'rx_required': true});
    expect(d.rxRequired, isTrue);
    final c = UserDrug.fromJson(
        {'id': 3, 'item_seq': null, 'item_name': '오메가3', 'is_custom': true, 'kind': 'SUPPLEMENT', 'rx_required': true});
    expect((c.isCustom, c.rxRequired, c.kind), (true, null, CustomKind.supplement));
  });
}
