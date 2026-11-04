#include <libsecret/secret.h>
#include <cstring>

// 只连接 Secret Service。任何需要 Prompt 的操作都直接失败。
struct UbaaCommandService { SecretService parent; };
struct UbaaCommandServiceClass { SecretServiceClass parent; };
G_DEFINE_TYPE(UbaaCommandService, ubaa_command_service, SECRET_TYPE_SERVICE)

static GVariant* reject_prompt(SecretService*, SecretPrompt*, GCancellable*,
                              const GVariantType*, GError** error) {
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED,
                      "安全材料需要先在当前系统会话解锁");
  return nullptr;
}
static void reject_prompt_async(SecretService* service, SecretPrompt*,
                                const GVariantType*, GCancellable* cancel,
                                GAsyncReadyCallback callback, gpointer data) {
  GTask* task=g_task_new(service,cancel,callback,data);
  g_task_return_new_error(task,G_IO_ERROR,G_IO_ERROR_PERMISSION_DENIED,
                         "安全材料需要先在当前系统会话解锁");
  g_object_unref(task);
}
static GVariant* reject_prompt_finish(SecretService*,GAsyncResult* result,GError** error) {
  return static_cast<GVariant*>(g_task_propagate_pointer(G_TASK(result),error));
}
static void ubaa_command_service_class_init(UbaaCommandServiceClass* klass) {
  auto* service=SECRET_SERVICE_CLASS(klass);
  service->prompt_sync=reject_prompt;
  service->prompt_async=reject_prompt_async;
  service->prompt_finish=reject_prompt_finish;
}
static void ubaa_command_service_init(UbaaCommandService*) {}

extern "C" __attribute__((visibility("default")))
int ubaa_command_materials(int operation,const char* value,char** output) {
  *output=nullptr;
  if(operation!=0&&operation!=1)return 7;
  if(operation==1&&value==nullptr)return 7;
  GError* error=nullptr;
  SecretService* service=secret_service_open_sync(ubaa_command_service_get_type(),
      "org.freedesktop.secrets",SECRET_SERVICE_OPEN_SESSION,nullptr,&error);
  if(!service){g_clear_error(&error);return 7;}
  SecretCollection* collection=secret_collection_for_alias_sync(service,
      SECRET_COLLECTION_DEFAULT,SECRET_COLLECTION_NONE,nullptr,&error);
  if(!collection||secret_collection_get_locked(collection)) {
    g_clear_object(&collection);g_object_unref(service);g_clear_error(&error);return 7;
  }
  // 锁定插件以 account 区分应用，整份材料位于一个 JSON item。
  // 按 account 查找并要求唯一，原 item 的 schema 和 label 保持原样。
  const SecretSchema schema={"default",SECRET_SCHEMA_DONT_MATCH_NAME,
      {{"account",SECRET_SCHEMA_ATTRIBUTE_STRING},{nullptr,SECRET_SCHEMA_ATTRIBUTE_STRING}}};
  GHashTable* attributes=secret_attributes_build(&schema,"account","cn.edu.ubaa.secureStorage",nullptr);
  GList* items=secret_service_search_sync(service,&schema,attributes,
      static_cast<SecretSearchFlags>(SECRET_SEARCH_ALL|SECRET_SEARCH_LOAD_SECRETS),nullptr,&error);
  int status=7;
  if(error==nullptr&&g_list_length(items)<=1) {
    auto* item=items?SECRET_ITEM(items->data):nullptr;
    if(item==nullptr||!secret_item_get_locked(item)) {
      if(operation==0) {
        SecretValue* secret=item?secret_item_get_secret(item):nullptr;
        if(item==nullptr||secret!=nullptr) {
          *output=g_strdup(secret?secret_value_get_text(secret):"{}");
          status=*output?0:7;
        }
        if(secret)secret_value_unref(secret);
      }else {
        SecretValue* secret=secret_value_new(value,-1,"text/plain");
        if(item)status=secret_item_set_secret_sync(item,secret,nullptr,&error)?0:7;
        else {
          const SecretSchema creation_schema={"default",SECRET_SCHEMA_NONE,
              {{"account",SECRET_SCHEMA_ATTRIBUTE_STRING},{nullptr,SECRET_SCHEMA_ATTRIBUTE_STRING}}};
          GHashTable* creation_attributes=secret_attributes_build(&creation_schema,"account","cn.edu.ubaa.secureStorage",nullptr);
          SecretItem* created=secret_item_create_sync(collection,&creation_schema,creation_attributes,
              "cn.edu.ubaa/FlutterSecureStorage",secret,SECRET_ITEM_CREATE_NONE,nullptr,&error);
          status=created?0:7;g_clear_object(&created);
          g_hash_table_unref(creation_attributes);
        }
        secret_value_unref(secret);
      }
    }
  }
  if(items)g_list_free_full(items,g_object_unref);
  g_hash_table_unref(attributes);g_object_unref(collection);g_object_unref(service);
  g_clear_error(&error);
  return status;
}
extern "C" __attribute__((visibility("default")))
void ubaa_command_materials_free(char* value) {
  if(value){std::memset(value,0,std::strlen(value));g_free(value);}
}
