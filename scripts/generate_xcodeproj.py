#!/usr/bin/env python3
"""Generate RadioMac.xcodeproj from the files on disk.

Xcode owns the project file for day-to-day work; this script is a deterministic
way to (re)create it, e.g. after adding or removing Swift files:

    python3 scripts/generate_xcodeproj.py
"""

from __future__ import annotations

import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES_DIR = ROOT / "RadioMac"
PROJECT_NAME = "RadioMac"
# Keep in sync with CHANGELOG/release tags; the release workflow overrides these.
MARKETING_VERSION = "2.1.0"
BUILD_NUMBER = "11"

ASSETS = SOURCES_DIR / "Resources" / "Assets.xcassets"
INFO_PLIST = SOURCES_DIR / "Resources" / "Info.plist"
ENTITLEMENTS = SOURCES_DIR / "Resources" / "RadioMac.entitlements"
LOCALIZATIONS = SOURCES_DIR / "Resources" / "Localizable.xcstrings"
TESTS_DIR = ROOT / "RadioMacTests"
UI_TESTS_DIR = ROOT / "RadioMacUITests"
WIDGET_DIR = ROOT / "RadioMacWidget"

# Finder Sync extension: the “Проиграть/Создать плейлист в RadioMac” context
# menu. It shares the request model and the audio extension list with the app.
FINDER_DIR = ROOT / "RadioMacFinder"
FINDER_INFO_PLIST = FINDER_DIR / "Info.plist"
FINDER_ENTITLEMENTS = FINDER_DIR / "RadioMacFinder.entitlements"

# iPhone app. It reuses the portable core (models, services, design tokens) and
# adds its own SwiftUI screens; macOS-only files never join this target.
IOS_DIR = ROOT / "RadioiOS"
IOS_INFO_PLIST = IOS_DIR / "Info.plist"
IOS_ASSETS = IOS_DIR / "Assets.xcassets"
IOS_DEPLOYMENT_TARGET = "17.0"
# A free Apple ID ("Personal Team") works: the app is installed from Xcode and
# never goes through the App Store. Override for a paid team with:
#   DEVELOPMENT_TEAM=ABCDE12345 RADIOIOS_BUNDLE_ID=com.example.radio python3 ...
IOS_DEVELOPMENT_TEAM = os.environ.get("DEVELOPMENT_TEAM", "")
IOS_BUNDLE_ID = os.environ.get("RADIOIOS_BUNDLE_ID", "com.fso13.radioMac.ios")

IOS_SHARED_SOURCES = [
    "Support/Platform.swift",
    "Support/AudioFileTypes.swift",
    # Models
    "Models/RadioStation.swift",
    "Models/NowPlaying.swift",
    "Models/StreamInfo.swift",
    "Models/LocalTrack.swift",
    "Models/MusicCollection.swift",
    "Models/MusicPlaylist.swift",
    "Models/EqualizerPreset.swift",
    "Models/TrackHistoryEntry.swift",
    "Models/MusicArtworkEditor.swift",
    # Data
    "Data/DefaultStations.swift",
    # Services
    "Services/Preferences.swift",
    "Services/AppSettings.swift",
    "Services/StationLibrary.swift",
    "Services/StationTransfer.swift",
    "Services/RadioBrowserService.swift",
    "Services/RadioPlayerService.swift",
    "Services/NativeAudioEngine.swift",
    "Services/NativeEqualizer.swift",
    "Services/AVAudioMixTap.swift",
    "Services/HLSMetadataDelegate.swift",
    "Services/ICYMetadataReader.swift",
    "Services/PlaybackState.swift",
    "Services/ReconnectPolicy.swift",
    "Services/NowPlayingLookup.swift",
    "Services/NowPlayingCenter.swift",
    "Services/EqualizerService.swift",
    "Services/ThemeService.swift",
    "Services/LocalAudioMetadata.swift",
    "Services/MetadataEnrichment.swift",
    "Services/MetadataProviders.swift",
    "Services/MusicLibrary.swift",
    "Services/MusicLibraryMaintenance.swift",
    "Services/MusicLibraryStorage.swift",
    "Services/MusicLibraryCollections.swift",
    "Services/MusicPlaylistFile.swift",
    "Services/LogoResolver.swift",
    "Services/TrackHistoryService.swift",
    # View models and shared design system
    "Window/MainViewModel.swift",
    "Window/MusicViewModel.swift",
    "UI/Palette.swift",
    "UI/DesignSystem.swift",
    "UI/ImageCache.swift",
    "UI/StationLogo.swift",
    "UI/BrandMark.swift",
    "UI/Components.swift",
    "UI/StationEditorView.swift",
]

FILE_IDS: dict[str, str] = {}
_counter = 0


def new_id(prefix: str) -> str:
    global _counter
    _counter += 1
    return f"{prefix}{_counter:022d}"


def ref(path: pathlib.Path) -> str:
    return f"{FILE_IDS[str(path)]} /* {path.name} */"


def quoted(value: str) -> str:
    if value and all(ch.isalnum() or ch in "._$/@" for ch in value):
        return value
    return f'"{value}"'


def group(identifier: str, children: list[str], name: str | None = None, path: str | None = None) -> str:
    lines = [f"\t\t{identifier} = {{", "\t\t\tisa = PBXGroup;", "\t\t\tchildren = ("]
    lines.extend(f"\t\t\t\t{child}," for child in children)
    lines.append("\t\t\t);")
    if name:
        lines.append(f"\t\t\tname = {quoted(name)};")
    if path:
        lines.append(f"\t\t\tpath = {quoted(path)};")
    lines.append('\t\t\tsourceTree = "<group>";')
    lines.append("\t\t};")
    return "\n".join(lines)


def phase(identifier: str, isa: str, files: list[str], name: str | None = None) -> str:
    lines = [
        f"\t\t{identifier} = {{",
        f"\t\t\tisa = {isa};",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
    ]
    lines.extend(f"\t\t\t\t{entry}," for entry in files)
    lines.append("\t\t\t);")
    if name:
        lines.append(f"\t\t\tname = {quoted(name)};")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    return "\n".join(lines)


def build() -> tuple[str, str]:
    sources = sorted(SOURCES_DIR.rglob("*.swift"))
    test_sources = sorted(TESTS_DIR.glob("*.swift")) if TESTS_DIR.exists() else []
    ui_test_sources = sorted(UI_TESTS_DIR.glob("*.swift")) if UI_TESTS_DIR.exists() else []
    shared_state = SOURCES_DIR / "Services" / "SharedPlaybackState.swift"
    widget_sources = sorted(WIDGET_DIR.glob("*.swift")) + [shared_state]
    widget_info = WIDGET_DIR / "Info.plist"
    widget_entitlements = WIDGET_DIR / "RadioMacWidget.entitlements"

    # The request model and the audio extension list already belong to the app;
    # the extension compiles them again for its own bundle.
    finder_sources = sorted(FINDER_DIR.glob("*.swift")) + [
        SOURCES_DIR / "Support" / "FinderBridge.swift",
        SOURCES_DIR / "Support" / "AudioFileTypes.swift",
        SOURCES_DIR / "Services" / "SharedPlaybackState.swift",
    ]

    ios_sources = sorted(IOS_DIR.rglob("*.swift"))
    ios_shared_sources = [SOURCES_DIR / relative for relative in IOS_SHARED_SOURCES]
    ios_target_sources = [*ios_shared_sources, *ios_sources]

    # The shared state is already an app source; keep one PBX file reference.
    all_files = list(dict.fromkeys([
        *sources, *test_sources, *ui_test_sources, *widget_sources, *finder_sources,
        *ios_sources, IOS_INFO_PLIST, IOS_ASSETS,
        ASSETS, INFO_PLIST, ENTITLEMENTS, LOCALIZATIONS, widget_info, widget_entitlements,
        FINDER_INFO_PLIST, FINDER_ENTITLEMENTS,
    ]))
    for path in ios_shared_sources:
        assert path.exists(), f"missing iOS shared source: {path}"
    assert shared_state.exists(), f"missing file: {shared_state}"
    for path in all_files:
        assert path.exists(), f"missing file: {path}"
        FILE_IDS[str(path)] = new_id("F1")

    target_id = new_id("A7")
    project_id = new_id("B8")
    sparkle_package = new_id("A1")
    sparkle_product = new_id("F1")
    sparkle_build = new_id("B2")
    main_group = new_id("A3")
    source_group = new_id("A3")
    products_group = new_id("A3")
    product_ref = new_id("F1")
    tests_target = new_id("A7")
    tests_product = new_id("F1")
    tests_group = new_id("A3")
    tests_sources_phase = new_id("C4")
    tests_frameworks_phase = new_id("C4")
    tests_resources_phase = new_id("C4")
    tests_configs = new_id("E6")
    tests_debug = new_id("D5")
    tests_release = new_id("D5")
    tests_dependency = new_id("A9")
    tests_proxy = new_id("B9")
    ui_target = new_id("A7")
    ui_product = new_id("F1")
    ui_group = new_id("A3")
    ui_sources_phase = new_id("C4")
    ui_frameworks_phase = new_id("C4")
    ui_resources_phase = new_id("C4")
    ui_configs = new_id("E6")
    ui_debug = new_id("D5")
    ui_release = new_id("D5")
    ui_dependency = new_id("A9")
    ui_proxy = new_id("B9")
    widget_target = new_id("A7")
    widget_product = new_id("F1")
    widget_group = new_id("A3")
    widget_sources_phase = new_id("C4")
    widget_frameworks_phase = new_id("C4")
    widget_resources_phase = new_id("C4")
    widget_embed_phase = new_id("C4")
    widget_embed_build = new_id("B2")
    widget_configs = new_id("E6")
    widget_debug = new_id("D5")
    widget_release = new_id("D5")
    widget_dependency = new_id("A9")
    widget_proxy = new_id("B9")
    finder_target = new_id("A7")
    finder_product = new_id("F1")
    finder_group = new_id("A3")
    finder_sources_phase = new_id("C4")
    finder_frameworks_phase = new_id("C4")
    finder_resources_phase = new_id("C4")
    finder_embed_build = new_id("B2")
    finder_configs = new_id("E6")
    finder_debug = new_id("D5")
    finder_release = new_id("D5")
    finder_dependency = new_id("A9")
    finder_proxy = new_id("B9")
    ios_target = new_id("A7")
    ios_product = new_id("F1")
    ios_group = new_id("A3")
    ios_sources_phase = new_id("C4")
    ios_frameworks_phase = new_id("C4")
    ios_resources_phase = new_id("C4")
    ios_configs = new_id("E6")
    ios_debug = new_id("D5")
    ios_release = new_id("D5")

    folder_groups = {
        name: new_id("A3") for name in ["Models", "Data", "Services", "Intents", "UI", "Window", "Support", "Resources"]
    }

    sources_phase = new_id("C4")
    frameworks_phase = new_id("C4")
    resources_phase = new_id("C4")
    project_configs = new_id("E6")
    target_configs = new_id("E6")
    project_debug = new_id("D5")
    project_release = new_id("D5")
    target_debug = new_id("D5")
    target_release = new_id("D5")

    build_files: list[tuple[str, pathlib.Path, str | None]] = []

    def build_file(path: pathlib.Path, settings: str | None = None) -> str:
        identifier = new_id("B2")
        build_files.append((identifier, path, settings))
        return identifier

    source_build_files = [build_file(path) for path in sources]
    test_build_files = [build_file(path) for path in test_sources]
    ui_test_build_files = [build_file(path) for path in ui_test_sources]
    widget_build_files = [build_file(path) for path in widget_sources]
    finder_build_files = [build_file(path) for path in finder_sources]
    ios_build_files = [build_file(path) for path in ios_target_sources]
    asset_build_file = build_file(ASSETS)
    ios_asset_build_file = build_file(IOS_ASSETS)
    localizations_build_file = build_file(LOCALIZATIONS)

    # ------------------------------------------------------------------ sections
    build_section = ["/* Begin PBXBuildFile section */"]
    for identifier, path, settings in build_files:
        suffix = f" {settings}" if settings else ""
        build_section.append(
            f"\t\t{identifier} /* {path.name} in Build */ = {{isa = PBXBuildFile; "
            f"fileRef = {ref(path)};{suffix} }};"
        )
    build_section.append(
        f"\t\t{sparkle_build} /* Sparkle in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {sparkle_product} /* Sparkle */; }};"
    )
    build_section.append(
        f"\t\t{widget_embed_build} /* RadioMacWidget.appex in Embed App Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {widget_product} /* RadioMacWidget.appex */; "
        "settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };"
    )
    build_section.append(
        f"\t\t{finder_embed_build} /* RadioMacFinder.appex in Embed App Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {finder_product} /* RadioMacFinder.appex */; "
        "settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };"
    )
    build_section.append("/* End PBXBuildFile section */")

    file_section = ["/* Begin PBXFileReference section */"]
    for path in all_files:
        suffix = path.suffix
        kind = {
            ".swift": "sourcecode.swift",
            ".xcassets": "folder.assetcatalog",
            ".xcstrings": "text.json.xcstrings",
            ".entitlements": "text.plist.entitlements",
            ".dylib": "compiled.mach-o.dylib",
            ".h": "sourcecode.c.h",
            ".plist": "text.plist.xml",
        }.get(suffix, "text")
        file_section.append(
            f"\t\t{FILE_IDS[str(path)]} /* {path.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {kind}; path = {quoted(path.name)}; "
            'sourceTree = "<group>"; };'
        )
    file_section.append(
        f"\t\t{product_ref} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; "
        f'explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; '
        "sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append(
        f"\t\t{tests_product} /* {PROJECT_NAME}Tests.xctest */ = {{isa = PBXFileReference; "
        f'explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {PROJECT_NAME}Tests.xctest; '
        "sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append(
        f"\t\t{ui_product} /* {PROJECT_NAME}UITests.xctest */ = {{isa = PBXFileReference; "
        f'explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {PROJECT_NAME}UITests.xctest; '
        "sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append(
        f"\t\t{widget_product} /* RadioMacWidget.appex */ = {{isa = PBXFileReference; "
        'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        "path = RadioMacWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append(
        f"\t\t{finder_product} /* RadioMacFinder.appex */ = {{isa = PBXFileReference; "
        'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        "path = RadioMacFinder.appex; sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append(
        f"\t\t{ios_product} /* RadioiOS.app */ = {{isa = PBXFileReference; "
        'explicitFileType = wrapper.application; includeInIndex = 0; path = RadioiOS.app; '
        "sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    file_section.append("/* End PBXFileReference section */")

    def files_in(folder: str) -> list[str]:
        return [ref(p) for p in sources if p.parent.name == folder]

    root_files = [ref(p) for p in sources if p.parent == SOURCES_DIR]

    group_section = ["/* Begin PBXGroup section */"]
    group_section.append(
        group(
            main_group,
            [
                f"{source_group} /* RadioMac */",
                f"{tests_group} /* {PROJECT_NAME}Tests */",
                f"{ui_group} /* {PROJECT_NAME}UITests */",
                f"{widget_group} /* RadioMacWidget */",
                f"{finder_group} /* RadioMacFinder */",
                f"{ios_group} /* RadioiOS */",
                f"{products_group} /* Products */",
            ],
        )
    )
    group_section.append(
        group(
            source_group,
            [
                *root_files,
                f"{folder_groups['Models']} /* Models */",
                f"{folder_groups['Data']} /* Data */",
                f"{folder_groups['Services']} /* Services */",
                f"{folder_groups['Intents']} /* Intents */",
                f"{folder_groups['UI']} /* UI */",
                f"{folder_groups['Window']} /* Window */",
                f"{folder_groups['Support']} /* Support */",
                f"{folder_groups['Resources']} /* Resources */",
            ],
            path="RadioMac",
        )
    )
    for name in ["Models", "Data", "Services", "Intents", "UI", "Window", "Support"]:
        group_section.append(group(folder_groups[name], files_in(name), path=name))
    group_section.append(
        group(
            folder_groups["Resources"],
            [ref(ASSETS), ref(INFO_PLIST), ref(ENTITLEMENTS), ref(LOCALIZATIONS)],
            path="Resources",
        )
    )
    group_section.append(
        group(
            products_group,
            [
                f"{product_ref} /* {PROJECT_NAME}.app */",
                f"{tests_product} /* {PROJECT_NAME}Tests.xctest */",
                f"{ui_product} /* {PROJECT_NAME}UITests.xctest */",
                f"{widget_product} /* RadioMacWidget.appex */",
                f"{finder_product} /* RadioMacFinder.appex */",
                f"{ios_product} /* RadioiOS.app */",
            ],
            name="Products",
        )
    )
    group_section.append(
        group(tests_group, [ref(path) for path in test_sources], path="RadioMacTests")
    )
    group_section.append(
        group(ui_group, [ref(path) for path in ui_test_sources], path="RadioMacUITests")
    )
    group_section.append(
        group(
            widget_group,
            [ref(path) for path in widget_sources if path.parent == WIDGET_DIR]
                + [ref(widget_info), ref(widget_entitlements)],
            path="RadioMacWidget"
        )
    )
    group_section.append(
        group(
            finder_group,
            [ref(path) for path in finder_sources if path.parent == FINDER_DIR]
                + [ref(FINDER_INFO_PLIST), ref(FINDER_ENTITLEMENTS)],
            path="RadioMacFinder"
        )
    )
    group_section.append(
        group(
            ios_group,
            [ref(path) for path in ios_sources] + [ref(IOS_INFO_PLIST), ref(IOS_ASSETS)],
            path="RadioiOS",
        )
    )
    group_section.append("/* End PBXGroup section */")

    sections = "\n".join([
        "/* Begin PBXFrameworksBuildPhase section */",
        phase(frameworks_phase, "PBXFrameworksBuildPhase", [f"{sparkle_build} /* Sparkle in Frameworks */"]),
        "/* End PBXFrameworksBuildPhase section */",
        "/* Begin PBXResourcesBuildPhase section */",
        phase(resources_phase, "PBXResourcesBuildPhase", [asset_build_file, localizations_build_file]),
        "/* End PBXResourcesBuildPhase section */",
        "/* Begin PBXSourcesBuildPhase section */",
        phase(sources_phase, "PBXSourcesBuildPhase", source_build_files),
        phase(tests_sources_phase, "PBXSourcesBuildPhase", test_build_files),
        phase(ui_sources_phase, "PBXSourcesBuildPhase", ui_test_build_files),
        phase(widget_sources_phase, "PBXSourcesBuildPhase", widget_build_files),
        phase(finder_sources_phase, "PBXSourcesBuildPhase", finder_build_files),
        phase(ios_sources_phase, "PBXSourcesBuildPhase", ios_build_files),
        "/* End PBXSourcesBuildPhase section */",
        "/* Begin PBXContainerItemProxy section */",
        f"\t\t{tests_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {project_id}; "
        f"proxyType = 1; remoteGlobalIDString = {target_id}; remoteInfo = {PROJECT_NAME}; }};",
        f"\t\t{ui_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {project_id}; "
        f"proxyType = 1; remoteGlobalIDString = {target_id}; remoteInfo = {PROJECT_NAME}; }};",
        f"\t\t{widget_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {project_id}; "
        f"proxyType = 1; remoteGlobalIDString = {widget_target}; remoteInfo = RadioMacWidget; }};",
        f"\t\t{finder_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {project_id}; "
        f"proxyType = 1; remoteGlobalIDString = {finder_target}; remoteInfo = RadioMacFinder; }};",
        "/* End PBXContainerItemProxy section */",
        "/* Begin PBXTargetDependency section */",
        f"\t\t{tests_dependency} = {{isa = PBXTargetDependency; target = {target_id}; "
        f"targetProxy = {tests_proxy}; }};",
        f"\t\t{ui_dependency} = {{isa = PBXTargetDependency; target = {target_id}; "
        f"targetProxy = {ui_proxy}; }};",
        f"\t\t{widget_dependency} = {{isa = PBXTargetDependency; target = {widget_target}; "
        f"targetProxy = {widget_proxy}; }};",
        f"\t\t{finder_dependency} = {{isa = PBXTargetDependency; target = {finder_target}; "
        f"targetProxy = {finder_proxy}; }};",
        "/* End PBXTargetDependency section */",
        "/* Begin PBXResourcesBuildPhase section (tests) */",
        phase(tests_resources_phase, "PBXResourcesBuildPhase", []),
        phase(ui_resources_phase, "PBXResourcesBuildPhase", []),
        phase(widget_resources_phase, "PBXResourcesBuildPhase", []),
        phase(finder_resources_phase, "PBXResourcesBuildPhase", []),
        phase(ios_resources_phase, "PBXResourcesBuildPhase", [ios_asset_build_file]),
        "/* End PBXResourcesBuildPhase section (tests) */",
        "/* Begin PBXFrameworksBuildPhase section (tests) */",
        phase(tests_frameworks_phase, "PBXFrameworksBuildPhase", []),
        phase(ui_frameworks_phase, "PBXFrameworksBuildPhase", []),
        phase(widget_frameworks_phase, "PBXFrameworksBuildPhase", []),
        phase(finder_frameworks_phase, "PBXFrameworksBuildPhase", []),
        phase(ios_frameworks_phase, "PBXFrameworksBuildPhase", []),
        "/* End PBXFrameworksBuildPhase section (tests) */",
        "/* Begin PBXCopyFilesBuildPhase section (widget) */",
        "\t\t" + widget_embed_phase + " /* Embed App Extensions */ = {",
        "\t\t\tisa = PBXCopyFilesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        f"\t\t\t\t{widget_embed_build} /* RadioMacWidget.appex in Embed App Extensions */,",
        f"\t\t\t\t{finder_embed_build} /* RadioMacFinder.appex in Embed App Extensions */,",
        "\t\t\t);",
        "\t\t\tdstPath = \"\";",
        "\t\t\tdstSubfolderSpec = 13;",
        "\t\t\tname = \"Embed App Extensions\";",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t};",
        "/* End PBXCopyFilesBuildPhase section (widget) */",
    ])

    project_settings = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ANALYZER_NONNULL = YES;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CLANG_WARN_BOOL_CONVERSION = YES;",
        "CLANG_WARN_UNREACHABLE_CODE = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu17;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        # Platform is chosen per target: the project hosts macOS and iOS apps.
        "SWIFT_VERSION = 6.0;",
    ]
    target_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "CODE_SIGN_ENTITLEMENTS = RadioMac/Resources/RadioMac.entitlements;",
        'CODE_SIGN_IDENTITY = "-";',
        "CODE_SIGN_STYLE = Manual;",
        "MACOSX_DEPLOYMENT_TARGET = 14.0;",
        "SDKROOT = macosx;",
        "COMBINE_HIDPI_IMAGES = YES;",
        f"CURRENT_PROJECT_VERSION = {BUILD_NUMBER};",
        "ENABLE_HARDENED_RUNTIME = NO;",
        "ENABLE_PREVIEWS = YES;",
        "INFOPLIST_FILE = RadioMac/Resources/Info.plist;",
        "LD_RUNPATH_SEARCH_PATHS = (",
        '\t"$(inherited)",',
        '\t"@executable_path/../Frameworks",',
        ");",
        "OTHER_LDFLAGS = (",
        '\t"$(inherited)",',
        '\t"-framework",',
        '\tAppIntents,',
        ");",
        f"MARKETING_VERSION = {MARKETING_VERSION};",
        "PRODUCT_BUNDLE_IDENTIFIER = com.fso13.radioMac;",
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        "SWIFT_STRICT_CONCURRENCY = complete;",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
    ]

    def config(identifier: str, name: str, extra: list[str]) -> str:
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in [*project_settings, *extra] if entry)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_target(identifier: str, name: str) -> str:
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in target_settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_tests(identifier: str, name: str) -> str:
        settings = [
            'BUNDLE_LOADER = "$(TEST_HOST)";',
            "CODE_SIGN_IDENTITY = \"-\";",
            "GENERATE_INFOPLIST_FILE = YES;",
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "SDKROOT = macosx;",
            "PRODUCT_BUNDLE_IDENTIFIER = com.fso13.radioMacTests;",
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
            "SWIFT_VERSION = 6.0;",
            'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/RadioMac.app/Contents/MacOS/RadioMac";',
            "LD_RUNPATH_SEARCH_PATHS = (",
            '\t"$(inherited)",',
            '\t"@executable_path/../Frameworks",',
            '\t"@loader_path/../Frameworks",',
            ");",
        ]
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_ui_tests(identifier: str, name: str) -> str:
        settings = [
            "CODE_SIGN_IDENTITY = \"-\";",
            "GENERATE_INFOPLIST_FILE = YES;",
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "SDKROOT = macosx;",
            "PRODUCT_BUNDLE_IDENTIFIER = com.fso13.radioMacUITests;",
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
            "SWIFT_VERSION = 6.0;",
            "TEST_TARGET_NAME = RadioMac;",
        ]
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_widget(identifier: str, name: str) -> str:
        settings = [
            "APPLICATION_EXTENSION_API_ONLY = YES;",
            "CODE_SIGN_ENTITLEMENTS = RadioMacWidget/RadioMacWidget.entitlements;",
            'CODE_SIGN_IDENTITY = "-";',
            "CODE_SIGN_STYLE = Manual;",
            f"CURRENT_PROJECT_VERSION = {BUILD_NUMBER};",
            "GENERATE_INFOPLIST_FILE = NO;",
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "SDKROOT = macosx;",
            "INFOPLIST_FILE = RadioMacWidget/Info.plist;",
            "LD_RUNPATH_SEARCH_PATHS = (",
            '\t"$(inherited)",',
            '\t"@executable_path/../../../../Frameworks",',
            ");",
            f"MARKETING_VERSION = {MARKETING_VERSION};",
            "PRODUCT_BUNDLE_IDENTIFIER = com.fso13.radioMac.widget;",
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            "SKIP_INSTALL = YES;",
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
            "SWIFT_VERSION = 6.0;",
        ]
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_finder(identifier: str, name: str) -> str:
        settings = [
            "APPLICATION_EXTENSION_API_ONLY = YES;",
            "CODE_SIGN_ENTITLEMENTS = RadioMacFinder/RadioMacFinder.entitlements;",
            'CODE_SIGN_IDENTITY = "-";',
            "CODE_SIGN_STYLE = Manual;",
            f"CURRENT_PROJECT_VERSION = {BUILD_NUMBER};",
            "GENERATE_INFOPLIST_FILE = NO;",
            "MACOSX_DEPLOYMENT_TARGET = 14.0;",
            "SDKROOT = macosx;",
            "INFOPLIST_FILE = RadioMacFinder/Info.plist;",
            "LD_RUNPATH_SEARCH_PATHS = (",
            '\t"$(inherited)",',
            '\t"@executable_path/../../../../Frameworks",',
            ");",
            f"MARKETING_VERSION = {MARKETING_VERSION};",
            "PRODUCT_BUNDLE_IDENTIFIER = com.fso13.radioMac.finder;",
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            "SKIP_INSTALL = YES;",
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
            "SWIFT_VERSION = 6.0;",
        ]
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    def config_ios(identifier: str, name: str) -> str:
        settings = [
            "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
            "CODE_SIGN_STYLE = Automatic;",
            f"CURRENT_PROJECT_VERSION = {BUILD_NUMBER};",
            "ENABLE_PREVIEWS = YES;",
            "GENERATE_INFOPLIST_FILE = NO;",
            "INFOPLIST_FILE = RadioiOS/Info.plist;",
            f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};",
            "LD_RUNPATH_SEARCH_PATHS = (",
            '\t"$(inherited)",',
            '\t"@executable_path/Frameworks",',
            ");",
            f"MARKETING_VERSION = {MARKETING_VERSION};",
            f"PRODUCT_BUNDLE_IDENTIFIER = {IOS_BUNDLE_ID};",
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            "SDKROOT = iphoneos;",
            'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
            "SUPPORTS_MACCATALYST = NO;",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;",
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;",
            "TARGETED_DEVICE_FAMILY = 1;",
        ]
        if IOS_DEVELOPMENT_TEAM:
            settings.append(f"DEVELOPMENT_TEAM = {IOS_DEVELOPMENT_TEAM};")
        lines = [f"\t\t{identifier} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
        lines.extend(f"\t\t\t\t{entry}" for entry in settings)
        lines.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
        return "\n".join(lines)

    config_section = "\n".join([
        "/* Begin XCBuildConfiguration section */",
        config(project_debug, "Debug", [
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "ENABLE_TESTABILITY = YES;",
            "GCC_OPTIMIZATION_LEVEL = 0;",
            "GCC_PREPROCESSOR_DEFINITIONS = (",
            '\t"DEBUG=1",',
            '\t"$(inherited)",',
            ");",
            "ONLY_ACTIVE_ARCH = YES;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
            'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
        ]),
        config(project_release, "Release", [
            'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
            "ENABLE_NS_ASSERTIONS = NO;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
            'SWIFT_OPTIMIZATION_LEVEL = "-O";',
        ]),
        config_target(target_debug, "Debug"),
        config_target(target_release, "Release"),
        config_tests(tests_debug, "Debug"),
        config_tests(tests_release, "Release"),
        config_ui_tests(ui_debug, "Debug"),
        config_ui_tests(ui_release, "Release"),
        config_widget(widget_debug, "Debug"),
        config_widget(widget_release, "Release"),
        config_finder(finder_debug, "Debug"),
        config_finder(finder_release, "Release"),
        config_ios(ios_debug, "Debug"),
        config_ios(ios_release, "Release"),
        "/* End XCBuildConfiguration section */",
    ])

    config_list_section = "\n".join([
        "/* Begin XCConfigurationList section */",
        f"\t\t{project_configs} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({project_debug} /* Debug */, {project_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{target_configs} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({target_debug} /* Debug */, {target_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{tests_configs} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}Tests\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({tests_debug} /* Debug */, {tests_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{ui_configs} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}UITests\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({ui_debug} /* Debug */, {ui_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{widget_configs} /* Build configuration list for PBXNativeTarget \"RadioMacWidget\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({widget_debug} /* Debug */, {widget_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{finder_configs} /* Build configuration list for PBXNativeTarget \"RadioMacFinder\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({finder_debug} /* Debug */, {finder_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        f"\t\t{ios_configs} /* Build configuration list for PBXNativeTarget \"RadioiOS\" */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        f"\t\t\tbuildConfigurations = ({ios_debug} /* Debug */, {ios_release} /* Release */);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
        "/* End XCConfigurationList section */",
    ])

    target_section = "\n".join([
        "/* Begin PBXNativeTarget section */",
        f"\t\t{target_id} /* {PROJECT_NAME} */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {target_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{sources_phase} /* Sources */,",
        f"\t\t\t\t{frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{resources_phase} /* Resources */,",
        f"\t\t\t\t{widget_embed_phase} /* Embed App Extensions */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        f"\t\t\tdependencies = ({widget_dependency} /* PBXTargetDependency */, {finder_dependency} /* PBXTargetDependency */,);",
        f"\t\t\tname = {PROJECT_NAME};",
        f"\t\t\tproductName = {PROJECT_NAME};",
        f"\t\t\tproductReference = {product_ref} /* {PROJECT_NAME}.app */;",
        "\t\t\tpackageProductDependencies = (",
        f"\t\t\t\t{sparkle_product} /* Sparkle */,",
        "\t\t\t);",
        '\t\t\tproductType = "com.apple.product-type.application";',
        "\t\t};",
        f"\t\t{tests_target} /* {PROJECT_NAME}Tests */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {tests_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{tests_sources_phase} /* Sources */,",
        f"\t\t\t\t{tests_frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{tests_resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        f"\t\t\tdependencies = ({tests_dependency} /* PBXTargetDependency */,);",
        f"\t\t\tname = {PROJECT_NAME}Tests;",
        f"\t\t\tproductName = {PROJECT_NAME}Tests;",
        f"\t\t\tproductReference = {tests_product} /* {PROJECT_NAME}Tests.xctest */;",
        '\t\t\tproductType = "com.apple.product-type.bundle.unit-test";',
        "\t\t};",
        f"\t\t{ui_target} /* {PROJECT_NAME}UITests */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {ui_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{ui_sources_phase} /* Sources */,",
        f"\t\t\t\t{ui_frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{ui_resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        f"\t\t\tdependencies = ({ui_dependency} /* PBXTargetDependency */,);",
        f"\t\t\tname = {PROJECT_NAME}UITests;",
        f"\t\t\tproductName = {PROJECT_NAME}UITests;",
        f"\t\t\tproductReference = {ui_product} /* {PROJECT_NAME}UITests.xctest */;",
        '\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";',
        "\t\t};",
        f"\t\t{widget_target} /* RadioMacWidget */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {widget_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{widget_sources_phase} /* Sources */,",
        f"\t\t\t\t{widget_frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{widget_resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        "\t\t\tdependencies = ();",
        "\t\t\tname = RadioMacWidget;",
        "\t\t\tproductName = RadioMacWidget;",
        f"\t\t\tproductReference = {widget_product} /* RadioMacWidget.appex */;",
        '\t\t\tproductType = "com.apple.product-type.app-extension";',
        "\t\t};",
        f"\t\t{finder_target} /* RadioMacFinder */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {finder_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{finder_sources_phase} /* Sources */,",
        f"\t\t\t\t{finder_frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{finder_resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        "\t\t\tdependencies = ();",
        "\t\t\tname = RadioMacFinder;",
        "\t\t\tproductName = RadioMacFinder;",
        f"\t\t\tproductReference = {finder_product} /* RadioMacFinder.appex */;",
        '\t\t\tproductType = "com.apple.product-type.app-extension";',
        "\t\t};",
        f"\t\t{ios_target} /* RadioiOS */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {ios_configs};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{ios_sources_phase} /* Sources */,",
        f"\t\t\t\t{ios_frameworks_phase} /* Frameworks */,",
        f"\t\t\t\t{ios_resources_phase} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        "\t\t\tdependencies = ();",
        "\t\t\tname = RadioiOS;",
        "\t\t\tproductName = RadioiOS;",
        f"\t\t\tproductReference = {ios_product} /* RadioiOS.app */;",
        '\t\t\tproductType = "com.apple.product-type.application";',
        "\t\t};",
        "/* End PBXNativeTarget section */",
    ])

    project_section = "\n".join([
        "/* Begin PBXProject section */",
        f"\t\t{project_id} /* Project object */ = {{",
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
        "\t\t\t\tLastSwiftUpdateCheck = 1600;",
        "\t\t\t\tLastUpgradeCheck = 1600;",
        "\t\t\t\tTargetAttributes = {",
        f"\t\t\t\t\t{target_id} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;",
        "\t\t\t\t\t};",
        f"\t\t\t\t\t{ios_target} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 17.0;",
        "\t\t\t\t\t};",
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {project_configs};",
        '\t\t\tcompatibilityVersion = "Xcode 14.0";',
        "\t\t\tdevelopmentRegion = ru;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\tknownRegions = (ru, en, Base);",
        f"\t\t\tmainGroup = {main_group};",
        f"\t\t\tproductRefGroup = {products_group};",
        "\t\t\tpackageReferences = (",
        f"\t\t\t\t{sparkle_package} /* Sparkle */,",
        "\t\t\t);",
        '\t\t\tprojectDirPath = "";',
        '\t\t\tprojectRoot = "";',
        f"\t\t\ttargets = ({target_id} /* {PROJECT_NAME} */, {tests_target} /* {PROJECT_NAME}Tests */, {ui_target} /* {PROJECT_NAME}UITests */, {widget_target} /* RadioMacWidget */, {finder_target} /* RadioMacFinder */, {ios_target} /* RadioiOS */);",
        "\t\t};",
        "/* End PBXProject section */",
    ])

    document = "\n".join([
        "// !$*UTF8*$!",
        "{",
        "\tarchiveVersion = 1;",
        "\tclasses = {};",
        "\tobjectVersion = 56;",
        "\tobjects = {",
        "",
        "\n".join(build_section),
        "",
        "\n".join(file_section),
        "",
        "\n".join(group_section),
        "",
        target_section,
        "",
        project_section,
        "",
        sections,
        "",
        "/* Begin XCRemoteSwiftPackageReference section */",
        f"\t\t{sparkle_package} /* Sparkle */ = {{",
        "\t\t\tisa = XCRemoteSwiftPackageReference;",
        '\t\t\trepositoryURL = "https://github.com/sparkle-project/Sparkle";',
        "\t\t\trequirement = {",
        "\t\t\t\tkind = upToNextMajorVersion;",
        "\t\t\t\tminimumVersion = 2.9.0;",
        "\t\t\t};",
        "\t\t};",
        "/* End XCRemoteSwiftPackageReference section */",
        "",
        "/* Begin XCSwiftPackageProductDependency section */",
        f"\t\t{sparkle_product} /* Sparkle */ = {{",
        "\t\t\tisa = XCSwiftPackageProductDependency;",
        f"\t\t\tpackage = {sparkle_package} /* Sparkle */;",
        "\t\t\tproductName = Sparkle;",
        "\t\t};",
        "/* End XCSwiftPackageProductDependency section */",
        "",
        config_section,
        "",
        config_list_section,
        "",
        "\t};",
        f"\trootObject = {project_id};",
        "}",
        "",
    ])
    return document, (target_id, tests_target, ui_target, widget_target, finder_target, ios_target)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "RadioMac.app"
               BlueprintName = "RadioMac"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_id}"
               BuildableName = "RadioMacTests.xctest"
               BlueprintName = "RadioMacTests"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ui_test_target_id}"
               BuildableName = "RadioMacUITests.xctest"
               BlueprintName = "RadioMacUITests"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{widget_target_id}"
               BuildableName = "RadioMacWidget.appex"
               BlueprintName = "RadioMacWidget"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{finder_target_id}"
               BuildableName = "RadioMacFinder.appex"
               BlueprintName = "RadioMacFinder"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "NO">
      <CommandLineArguments>
         <CommandLineArgument argument = "-skip-lastfm-keychain" isEnabled = "YES">
         </CommandLineArgument>
      </CommandLineArguments>
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_id}"
               BuildableName = "RadioMacTests.xctest"
               BlueprintName = "RadioMacTests"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ui_test_target_id}"
               BuildableName = "RadioMacUITests.xctest"
               BlueprintName = "RadioMacUITests"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "RadioMac.app"
            BlueprintName = "RadioMac"
            ReferencedContainer = "container:RadioMac.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "RadioMac.app"
            BlueprintName = "RadioMac"
            ReferencedContainer = "container:RadioMac.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


IOS_SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ios_target_id}"
               BuildableName = "RadioiOS.app"
               BlueprintName = "RadioiOS"
               ReferencedContainer = "container:RadioMac.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ios_target_id}"
            BuildableName = "RadioiOS.app"
            BlueprintName = "RadioiOS"
            ReferencedContainer = "container:RadioMac.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ios_target_id}"
            BuildableName = "RadioiOS.app"
            BlueprintName = "RadioiOS"
            ReferencedContainer = "container:RadioMac.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> int:
    document, (target_id, tests_target, ui_target, widget_target, finder_target, ios_target_id) = build()
    project_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text(document, encoding="utf-8")

    scheme_dir = project_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / f"{PROJECT_NAME}.xcscheme").write_text(
        SCHEME.replace("{target_id}", target_id)
        .replace("{test_target_id}", tests_target)
        .replace("{ui_test_target_id}", ui_target)
        .replace("{widget_target_id}", widget_target)
        .replace("{finder_target_id}", finder_target),
        encoding="utf-8",
    )
    (scheme_dir / "RadioiOS.xcscheme").write_text(
        IOS_SCHEME.replace("{ios_target_id}", ios_target_id),
        encoding="utf-8",
    )
    print(
        f"wrote {project_dir} (app {target_id}, tests {tests_target}, "
        f"ui {ui_target}, ios {ios_target_id})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
