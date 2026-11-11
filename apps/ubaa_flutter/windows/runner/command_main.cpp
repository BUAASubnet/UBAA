#include <windows.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <fcntl.h>
#include <io.h>
#include <algorithm>
#include <cstdio>
#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

namespace {
using Value=flutter::EncodableValue;
using Result=flutter::MethodResult<Value>;
constexpr UINT kReady=WM_APP+41;
HANDLE cancellation_event=nullptr;
std::mutex pending_mutex;
std::queue<std::function<void()>> pending;
DWORD main_thread=0;

BOOL WINAPI CancelCommand(DWORD kind) {
  if(kind==CTRL_C_EVENT||kind==CTRL_BREAK_EVENT||kind==CTRL_CLOSE_EVENT){
    SetEvent(cancellation_event);return TRUE;
  }
  return FALSE;
}
void Post(std::function<void()> action) {
  {std::lock_guard<std::mutex> lock(pending_mutex);pending.push(std::move(action));}
  PostThreadMessage(main_thread,kReady,0,0);
}
void Drain() {
  std::queue<std::function<void()>> work;
  {std::lock_guard<std::mutex> lock(pending_mutex);work.swap(pending);}
  while(!work.empty()){work.front()();work.pop();}
}
bool Utf8(const wchar_t* value,int length,std::string* output) {
  if(length==0){output->clear();return true;}
  int count=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,length,nullptr,0,nullptr,nullptr);
  if(count<=0)return false;
  output->resize(static_cast<size_t>(count));
  return WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,length,output->data(),count,nullptr,nullptr)==count;
}
HANDLE Preserve(DWORD kind) {
  HANDLE result=nullptr;
  if(!DuplicateHandle(GetCurrentProcess(),GetStdHandle(kind),GetCurrentProcess(),&result,0,FALSE,DUPLICATE_SAME_ACCESS))return nullptr;
  return result;
}
bool WriteBytes(HANDLE handle,const std::vector<uint8_t>& bytes) {
  DWORD mode=0;
  if(GetConsoleMode(handle,&mode)) {
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(bytes.data()),static_cast<int>(bytes.size()),nullptr,0);
    if(count==0)return bytes.empty();
    std::wstring wide(static_cast<size_t>(count),L'\0');
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,reinterpret_cast<const char*>(bytes.data()),static_cast<int>(bytes.size()),wide.data(),count)!=count)return false;
    size_t position=0;
    while(position<wide.size()){
      DWORD written=0;
      if(!WriteConsoleW(handle,wide.data()+position,static_cast<DWORD>(wide.size()-position),&written,nullptr)||written==0)return false;
      position+=written;
    }
    return true;
  }
  size_t position=0;
  while(position<bytes.size()) {
    DWORD written=0;
    if(!WriteFile(handle,bytes.data()+position,static_cast<DWORD>(bytes.size()-position),&written,nullptr)||written==0)return false;
    position+=written;
  }
  return true;
}
bool ReadBytes(HANDLE handle,bool line,bool secret,std::vector<uint8_t>* bytes,bool* eof) {
  DWORD mode=0;
  bool terminal=GetConsoleMode(handle,&mode)!=FALSE;
  if(terminal&&secret&&!SetConsoleMode(handle,mode&~ENABLE_ECHO_INPUT))return false;
  bool success=true;
  if(terminal) {
    std::wstring wide;
    while(true) {
      wchar_t character=0;DWORD count=0;
      if(!ReadConsoleW(handle,&character,1,&count,nullptr)){success=false;break;}
      if(count==0||(wide.empty()&&character==26)){*eof=true;break;}
      if(character==L'\r')continue;
      wide.push_back(character);
      if(wide.size()>1048576){success=false;break;}
      if(line&&character==L'\n')break;
    }
    std::string text;
    if(success&&!Utf8(wide.data(),static_cast<int>(wide.size()),&text))success=false;
    bytes->assign(text.begin(),text.end());
  }else{
    uint8_t buffer[4096];
    while(true){
      DWORD count=0;
      if(!ReadFile(handle,buffer,line?1:sizeof(buffer),&count,nullptr)){
        if(GetLastError()!=ERROR_BROKEN_PIPE)success=false;
        *eof=true;break;
      }
      if(count==0){*eof=true;break;}
      bytes->insert(bytes->end(),buffer,buffer+count);
      if(bytes->size()>1048576){success=false;break;}
      if(line&&buffer[count-1]==10)break;
    }
  }
  if(terminal&&secret){SetConsoleMode(handle,mode);}
  return success;
}
}  // namespace

// 控制台子系统入口保留 shell 的等待、退出码及继承句柄，不注册 GUI mutex。
int wmain(int argc,wchar_t* argv[]) {
  const ULONGLONG started=GetTickCount64();
  HANDLE output=Preserve(STD_OUTPUT_HANDLE);
  HANDLE diagnostics=Preserve(STD_ERROR_HANDLE);
  HANDLE input=Preserve(STD_INPUT_HANDLE);
  if(!output||!diagnostics||!input)return 7;
  DWORD terminal_mode=0;
  const bool has_terminal=GetConsoleMode(input,&terminal_mode)!=FALSE;
  auto restore_terminal=[&]{if(has_terminal)SetConsoleMode(input,terminal_mode);};
  SetStdHandle(STD_OUTPUT_HANDLE,diagnostics);
  _dup2(_fileno(stderr),_fileno(stdout));
  std::vector<std::string> arguments{"ubaa-cli"};
  for(int i=1;i<argc;i++) {
    std::string value;
    if(!Utf8(argv[i],static_cast<int>(wcslen(argv[i])),&value))return 2;
    arguments.push_back(std::move(value));
  }
  CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
  main_thread=GetCurrentThreadId();
  MSG message;PeekMessage(&message,nullptr,0,0,PM_NOREMOVE);
  cancellation_event=CreateEvent(nullptr,TRUE,FALSE,nullptr);
  SetConsoleCtrlHandler(CancelCommand,TRUE);
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(arguments));
  flutter::FlutterEngine engine(project);
  flutter::MethodChannel<Value> channel(engine.messenger(),"cn.edu.ubaa/command",&flutter::StandardMethodCodec::GetInstance());
  bool finished=false;bool local_command=false;int exit_code=7;
  channel.SetMethodCallHandler([&](const auto& call,std::unique_ptr<Result> owned){
    auto result=std::shared_ptr<Result>(std::move(owned));
    const auto& method=call.method_name();
    if(method=="configure"){
      if(auto local=std::get_if<bool>(call.arguments()))local_command=*local;
      result->Success();return;
    }
    if(method=="config"){
      auto remaining=static_cast<int64_t>(120000-(std::min)(GetTickCount64()-started,ULONGLONG{120000}));
      result->Success(Value(flutter::EncodableMap{{Value("remainingMillis"),Value(remaining)}}));return;
    }
    if(method=="complete"){
      if(auto code=std::get_if<int32_t>(call.arguments()))exit_code=*code;
      else if(auto wide_code=std::get_if<int64_t>(call.arguments()))exit_code=static_cast<int>(*wide_code);
      restore_terminal();result->Success();finished=true;return;
    }
    if(method=="stdout"||method=="stderr"){
      auto bytes=call.arguments()?std::get_if<std::vector<uint8_t>>(call.arguments()):nullptr;
      if(!bytes){result->Error("io_error","输出数据无效");return;}
      HANDLE handle=method=="stdout"?output:diagnostics;
      std::thread([result,handle,data=*bytes]{
        bool success=WriteBytes(handle,data);
        Post([result,success]{if(success)result->Success();else result->Error("io_error","终端写入失败");});
      }).detach();return;
    }
    if(method=="readLine"||method=="readBody"){
      bool line=method=="readLine";
      auto flag=call.arguments()?std::get_if<bool>(call.arguments()):nullptr;
      bool secret=line&&flag&&*flag;
      std::thread([result,input,line,secret,diagnostics]{
        std::vector<uint8_t> bytes;bool eof=false;
        bool success=ReadBytes(input,line,secret,&bytes,&eof);
        if(secret){WriteBytes(diagnostics,std::vector<uint8_t>{10});}
        Post([result,success,eof,line,bytes=std::move(bytes)]{
          if(!success)result->Error("io_error","终端读取失败");
          else if(eof&&line&&bytes.empty())result->Success();
          else result->Success(Value(bytes));
        });
      }).detach();return;
    }
    result->NotImplemented();
  });
  if(!engine.Run("commandMain"))return 7;
  bool stopping=false;ULONGLONG stop_at=0;
  while(!finished){
    const auto now=GetTickCount64();
    if(!stopping&&(now-started>=120000||WaitForSingleObject(cancellation_event,0)==WAIT_OBJECT_0)){
      const bool deadline=now-started>=120000;
      restore_terminal();
      stopping=true;stop_at=now;exit_code=deadline&&!local_command?5:7;
      channel.InvokeMethod(deadline?"deadline":"cancel",std::make_unique<Value>());
    }
    if(stopping&&now-stop_at>=2000)TerminateProcess(GetCurrentProcess(),static_cast<UINT>(exit_code));
    const auto engine_wait=engine.ProcessMessages();
    auto millis=std::chrono::duration_cast<std::chrono::milliseconds>(engine_wait).count();
    auto until_stop=stopping?2000-(now-stop_at):120000-(now-started);
    DWORD timeout=static_cast<DWORD>((std::min)(static_cast<ULONGLONG>((std::max)(int64_t{0},millis)),until_stop));
    HANDLE event=stopping?nullptr:cancellation_event;
    MsgWaitForMultipleObjectsEx(event?1:0,event?&event:nullptr,timeout,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
    while(PeekMessage(&message,nullptr,0,0,PM_REMOVE)){
      if(message.message==kReady){Drain();continue;}
      TranslateMessage(&message);DispatchMessage(&message);
    }
  }
  SetConsoleCtrlHandler(CancelCommand,FALSE);
  CloseHandle(cancellation_event);
  // 工作线程的迟到 I/O 由进程退出释放，不能再访问已销毁的 Engine。
  ExitProcess(static_cast<UINT>(exit_code));
}
