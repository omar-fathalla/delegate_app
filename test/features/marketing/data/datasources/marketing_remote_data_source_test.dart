import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarketingRemoteDataSourceImpl.normalizeBranchName', () {
    test('should normalize Alef variations (أ, إ, آ -> ا)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('أبو يوسف'), 'ابو يوسف');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('إبراهيمية'), 'ابراهيميه');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('آل ياسين'), 'ال ياسين');
    });

    test('should normalize Ta Marbouta (ة -> ه)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('سموحة'), 'سموحه');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('العجمي ستار'), 'العجمي ستار');
    });

    test('should normalize Ya and Alif Maqsura (ى -> ي)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('مستشفى الكبرى'), 'مستشفي الكبري');
    });

    test('should trim leading/trailing whitespace and collapse internal spaces', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('   Abo Yousif   '), 'abo yousif');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('Abo   Yousif'), 'abo yousif');
    });

    test('should lowercase latin branch names', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('ABO YOUSIF'), 'abo yousif');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('Branch Alpha'), 'branch alpha');
    });
  });
}
