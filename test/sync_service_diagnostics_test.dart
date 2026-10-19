import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/sync_service.dart';

class _ReportingSyncDelegate implements dartloom.SyncService {
  _ReportingSyncDelegate(this.report);

  final dartloom.SyncRunReport report;

  @override
  Future<List<dartloom.SyncProfile>> listProfiles() async => [];

  @override
  Future<dartloom.SyncRunReport> syncNow() async => report;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'failed sync logs actionable category, message and retryability',
    () async {
      const failure = dartloom.SyncFailure(
        dartloom.SyncFailureKind.authentication,
        'WebDAV rejected credentials (HTTP 401)',
        retryable: false,
      );
      final log = MemoryLogger();
      final service = SyncService(
        delegate: _ReportingSyncDelegate(
          const dartloom.SyncRunReport(
            trigger: dartloom.SyncTrigger.manual,
            failure: failure,
          ),
        ),
        logger: log,
      );

      await expectLater(
        service.syncNow(),
        throwsA(
          isA<dartloom.SyncOperationException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                dartloom.SyncFailureKind.authentication,
              )
              .having((e) => e.failure.message, 'message', failure.message),
        ),
      );

      final error = log.entries.singleWhere((e) => e.level == 'error');
      expect(error.message, contains('authentication'));
      expect(error.message, contains('retryable=false'));
      expect(error.message, contains('HTTP 401'));
      expect(error.message, isNot(contains("Instance of 'SyncFailure'")));
      expect(error.error, isNull);
    },
  );

  test('sync success remains unchanged', () async {
    final log = MemoryLogger();
    final service = SyncService(
      delegate: _ReportingSyncDelegate(
        const dartloom.SyncRunReport(
          trigger: dartloom.SyncTrigger.manual,
          uploaded: 2,
          downloaded: 3,
        ),
      ),
      logger: log,
    );

    final result = await service.syncNow();
    expect(result.isSuccess, isTrue);
    expect(result.uploaded, 2);
    expect(result.downloaded, 3);
    expect(log.entries.where((entry) => entry.level == 'error'), isEmpty);
    expect(log.entries.last.message, contains('downloaded=3'));
  });
}
