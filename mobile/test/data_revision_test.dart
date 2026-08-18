import 'package:eureka/data_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation refresh does not publish a mutation revision', () {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    requestDataRefresh();

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore);
  });

  test('confirmed mutation publishes both revisions', () {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    bumpData();

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore + 1);
  });
}
