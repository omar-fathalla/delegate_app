import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';

const _a = ChainOption(uid: 'o1', name: 'كارفور');
const _b = ChainOption(uid: 'o2', name: 'سبينيس');
const _c = ChainOption(uid: 'o3', name: 'هايبر وان');
const _all = [_a, _b, _c];

void main() {
  test('select-all then deselect all', () {
    var selected = <String>{};
    selected = toggleSelectAll(all: _all, selectedUids: selected);
    expect(selected, {'o1', 'o2', 'o3'});
    selected = toggleSelectAll(all: _all, selectedUids: selected);
    expect(selected, isEmpty);
  });

  test('duplicate chains are skipped with an Arabic warning', () {
    final result = partitionSelectedChains(
      all: _all,
      selectedUids: {'o1', 'o2', 'o3'},
      duplicateUids: {'o1', 'o2'},
    );
    expect(result.canSubmit, isTrue);
    expect(result.kept, [_c]);
    expect(result.skipped, [_a, _b]);
    expect(result.warningAr, 'المندوب مسجل بالفعل في: كارفور، سبينيس. سيتم تسجيله في: هايبر وان.');
  });

  test('all selected chains duplicate: cannot submit', () {
    final result = partitionSelectedChains(
      all: _all,
      selectedUids: {'o1', 'o2'},
      duplicateUids: {'o1', 'o2'},
    );
    expect(result.canSubmit, isFalse);
    expect(result.warningAr, contains('كل السلاسل المختارة'));
  });

  test('legacy request with only organizationUID resolves to a one-item list', () {
    expect(resolveOrganizationUIDs(organizationUID: 'o1'), ['o1']);
    expect(
      resolveOrganizationUIDs(organizationUID: 'o1', organizationUIDs: ['o2', 'o3', 'o2']),
      ['o1', 'o2', 'o3'],
    );
  });
}
