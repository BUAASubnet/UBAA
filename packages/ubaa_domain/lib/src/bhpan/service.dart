import 'models.dart';
import '../write/intent.dart';

abstract interface class BhpanService {
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  );

  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  );
  BhpanTransferTask createTransfer();
  Future<BhpanCapabilities> capabilities();
  Future<void> login();
  Future<BhpanPage> read(BhpanRead query);
  Future<BhpanSize> size(String item);
  Future<String> suggestName(String parent, String name);
  Future<List<BhpanShare>> shares({String? item});
  Future<String> shareLink(String share);
  Future<WriteIntent> prepare(BhpanMutation request);
}

abstract interface class BhpanProvider {
  BhpanService get bhpan;
}
