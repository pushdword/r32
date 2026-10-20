#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif
namespace fs=std::filesystem;
static std::string quote(const fs::path& p){std::string s=fs::absolute(p).generic_string();if(s.find_first_of("{}\r\n")!=std::string::npos)throw std::runtime_error("Unsupported path character");return "{"+s+"}";}
static int execute(const std::string& program,const fs::path& script){
#ifdef _WIN32
 auto wide=[](const std::string& s){int n=MultiByteToWideChar(CP_UTF8,0,s.c_str(),-1,nullptr,0);std::wstring w(n,L'\0');MultiByteToWideChar(CP_UTF8,0,s.c_str(),-1,w.data(),n);w.resize(n-1);return w;};
 std::wstring cmd=L"\""+wide(program)+L"\" \""+script.wstring()+L"\"";STARTUPINFOW si{};si.cb=sizeof(si);PROCESS_INFORMATION pi{};if(!CreateProcessW(nullptr,cmd.data(),nullptr,nullptr,TRUE,0,nullptr,nullptr,&si,&pi))throw std::runtime_error("Cannot start FPGA tool");WaitForSingleObject(pi.hProcess,INFINITE);DWORD code=1;GetExitCodeProcess(pi.hProcess,&code);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);return int(code);
#else
 pid_t pid=fork();if(pid<0)throw std::runtime_error("Cannot create process");if(!pid){execlp(program.c_str(),program.c_str(),script.c_str(),nullptr);_exit(127);}int status=0;if(waitpid(pid,&status,0)<0)throw std::runtime_error("Cannot wait for FPGA tool");return WIFEXITED(status)?WEXITSTATUS(status):1;
#endif
}
int main(int argc,char**argv){try{
 if(argc<9)throw std::runtime_error("Usage: fpga-build TOOL OUT TOP DEVICE CST SDC BOOT SOURCE...");
 std::string tool=argv[1],top=argv[3],device=argv[4];if(top.empty()||device.empty()||top.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")!=std::string::npos||device.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_/-")!=std::string::npos)throw std::runtime_error("Invalid FPGA target");
 fs::path root=fs::current_path(),out=fs::absolute(argv[2]).lexically_normal();auto rel=out.lexically_relative(root);if(rel.empty()||rel.begin()->string()==".."||rel.begin()->string()!="build")throw std::runtime_error("Output must be below build/");fs::create_directories(out);
 if(!fs::is_regular_file(argv[5])||!fs::is_regular_file(argv[6]))throw std::runtime_error("FPGA constraints required");
 if(!fs::is_regular_file(argv[7]))throw std::runtime_error("External boot ROM image required");fs::copy_file(argv[7],out/"firmware.hex",fs::copy_options::overwrite_existing);
 for(auto& e:fs::recursive_directory_iterator(root/"rtl"))if(e.is_regular_file()&&(e.path().extension()==".hex"||e.path().extension()==".mem")){auto dst=out/e.path().lexically_relative(root);fs::create_directories(dst.parent_path());fs::copy_file(e.path(),dst,fs::copy_options::overwrite_existing);}
 auto script=out/"build.tcl";std::ofstream f(script);if(!f)throw std::runtime_error("Cannot create FPGA input");f<<"cd "<<quote(out)<<"\nset_device "<<device<<" -device_version A\n";
 for(int i=8;i<argc;i++){fs::path p=argv[i];if(!fs::is_regular_file(p))throw std::runtime_error("Missing HDL source: "+p.string());f<<"add_file -type verilog "<<quote(p)<<'\n';}
 f<<"add_file -type cst "<<quote(argv[5])<<"\nadd_file -type sdc "<<quote(argv[6])<<"\nset_option -synthesis_tool gowinsynthesis\nset_option -top_module "<<top<<"\nset_option -verilog_std sysv2017\nset_option -output_base_name "<<top<<"\nset_option -rw_check_on_ram 1\nset_option -looplimit 10000\nset_option -place_option 3\nset_option -route_option 2\nset_option -timing_driven 1\nset_option -correct_hold_violation 1\nset_option -gen_text_timing_rpt 1\nset_option -use_cpu_as_gpio 1\nset_option -use_i2c_as_gpio 1\nset_option -use_mspi_as_gpio 1\nset_option -gen_sdf 1\nset_option -gen_verilog_sim_netlist 1\nrun all\n";f.close();if(tool=="--emit")return 0;return execute(tool,script);
 }catch(const std::exception&e){std::cerr<<"fpga-build: "<<e.what()<<'\n';return 1;}}
