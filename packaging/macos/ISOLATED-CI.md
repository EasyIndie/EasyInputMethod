# 设备B隔离输入法公证对照

在main手动运行Isolated IMK Notarization，target_root填写已在设备B准备好的独有私有临时根绝对路径。不得填真实Lampyris数据目录。仅arm64 runner，复用现有Apple凭据，所有Actions固定commit；非main不会使用凭据。附件保留7天，无Release/安装操作。

下载后核对ZIP摘要、SOURCE-COMMIT.txt和TARGET-ROOT.txt，确认本机根的UUID/所有权/0700权限及owner文件，再用ditto解压，核对签名、staple和Gatekeeper。外层包名称Lampyris.app仅用于复用CI签名脚本，内部仍为独有测试身份；放入根内时重命名为LampyrisIMKTest.app。不修改IMKTestRoot或其他签名资源。注册/启动/选择须另按安全协议验收，不能以公证成功代替。

此分支是系统信任对照的最小改动，基于已提交c294b67；不含主工作区全部产品改动，不是最终MVP候选。设备绑定导致该包只允许在声明根所在的设备上运行。
