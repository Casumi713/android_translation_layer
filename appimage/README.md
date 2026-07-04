# Android Translation Layer AppImage 打包指南

## 快速开始

### 1. 构建项目
```bash
cmake -B build
cmake --build build
```

### 2. 打包 AppImage
```bash
chmod +x appimage/build-appimage.sh
./appimage/build-appimage.sh
```

生成的 AppImage 位于 `build/android-translation-layer-*.appimage`

## 使用 AppImage

### 运行 APK
```bash
./android-translation-layer-*.appimage /path/to/app.apk
```

### 指定 Activity
```bash
./android-translation-layer-*.appimage /path/to/app.apk -l com/example/MainActivity
```

### 安装到系统（可选）
```bash
sudo cp android-translation-layer-*.appimage /usr/local/bin/
```

## 自定义打包

### 修改 AppImage 名称
编辑 `appimage/build-appimage.sh` 中的 `APPIMAGE_NAME` 变量

### 添加图标
将图标文件放到 `doc/logo.png`（256x256 PNG 格式）

### 修改桌面文件
编辑 `appimage/build-appimage.sh` 中的桌面文件内容

## 依赖要求

打包脚本会自动下载 `appimagetool`，但需要以下工具：
- `wget` - 下载 appimagetool
- `base64` - 创建占位图标

### 可选依赖
- `rsvg-convert` 或 `inkscape` - 转换 SVG 图标为 PNG

## 故障排除

### 问题：appimagetool 下载失败
手动下载：
```bash
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /tmp/appimagetool
chmod +x /tmp/appimagetool
```

### 问题：缺少库文件
确保已完成完整构建：
```bash
cmake --build build
```

### 问题：图标不显示
确保图标文件存在且格式正确：
```bash
file build/AppDir/share/icons/hicolor/256x256/apps/android-translation-layer.png
```

## 目录结构

打包后的 AppDir 结构：
```
AppDir/
├── AppRun                    # 启动脚本
├── bin/
│   ├── android-translation-layer          # 主程序
│   └── android-translation-layer-wrapper  # 包装脚本
├── lib/
│   ├── *.so                   # 共享库
│   ├── art/                   # ART 运行时
│   └── java/                  # Java 资源
└── share/
    ├── applications/          # 桌面文件
    ├── icons/                 # 图标
    ├── metainfo/              # AppStream 元数据
    └── atl/                   # ATL 资源
```
