#!/usr/bin/env python3
"""Generate the dependency-free Xcode project; deterministic IDs keep diffs small."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value):
    return json.dumps(str(value))
def obj(name, body):
    key = ident(name)
    objects[key] = body
    return key
def sequence(items):
    return '(' + ', '.join(items) + (',' if items else '') + ')'
def settings(values):
    return '{ ' + ' '.join(f'{k} = {q(v)};' for k, v in values.items()) + ' }'

app_files = sorted((ROOT / 'Financeiro').rglob('*.swift'))
test_files = sorted((ROOT / 'Tests').glob('*.swift'))
resources = [ROOT/'Financeiro/Resources/PrivacyInfo.xcprivacy', ROOT/'Financeiro/Resources/Assets.xcassets']
refs = []
def reference(path, typ):
    rel = str(path.relative_to(ROOT))
    key = obj('file:'+rel, f'{{ isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(rel)}; sourceTree = "<group>"; }}')
    refs.append(key)
    return key

def build_files(paths, typ):
    result=[]
    for path in paths:
        ref=reference(path,typ)
        result.append(obj('build:'+str(path.relative_to(ROOT)), f'{{ isa = PBXBuildFile; fileRef = {ref}; }}'))
    return result
app_build=build_files(app_files,'sourcecode.swift')
test_build=build_files(test_files,'sourcecode.swift')
resource_build=[]
for resource in resources:
    typ='folder.assetcatalog' if resource.suffix=='.xcassets' else 'text.xml'
    resource_build.extend(build_files([resource],typ))
reference(ROOT/'Financeiro/Resources/Info.plist','text.plist.xml')
app_product=obj('appProduct','{ isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Financeiro.app; sourceTree = BUILT_PRODUCTS_DIR; }')
test_product=obj('testProduct','{ isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FinanceiroTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
product_group=obj('products',f'{{ isa = PBXGroup; children = {sequence([app_product,test_product])}; name = Products; sourceTree = "<group>"; }}')
root_group=obj('rootGroup',f'{{ isa = PBXGroup; children = {sequence(refs+[product_group])}; sourceTree = "<group>"; }}')

def phase(name,isa,files):
    return obj(name,f'{{ isa = {isa}; buildActionMask = 2147483647; files = {sequence(files)}; runOnlyForDeploymentPostprocessing = 0; }}')
app_phases=[phase('appSources','PBXSourcesBuildPhase',app_build),phase('appFrameworks','PBXFrameworksBuildPhase',[]),phase('appResources','PBXResourcesBuildPhase',resource_build)]
test_phases=[phase('testSources','PBXSourcesBuildPhase',test_build),phase('testFrameworks','PBXFrameworksBuildPhase',[])]

def configs(name,values):
    items=[]
    for mode in ['Debug','Release']:
        options=dict(values)
        options['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if mode=='Debug' else '-O'
        if mode=='Debug':
            options['ENABLE_TESTABILITY']='YES'
            options['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
        items.append(obj(name+mode,f'{{ isa = XCBuildConfiguration; buildSettings = {settings(options)}; name = {mode}; }}'))
    return obj(name+'ConfigList',f'{{ isa = XCConfigurationList; buildConfigurations = {sequence(items)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
common={
    'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'5.0',
    'SWIFT_STRICT_CONCURRENCY':'targeted','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
    'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
    'TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic',
    'MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1',
    'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym',
}
project_configs=configs('project',common)
app_configs=configs('app',{
    'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'br.com.iancfreitas.financeiro',
    'INFOPLIST_FILE':'Financeiro/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
    'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor',
    'OTHER_LDFLAGS':'$(inherited) -lsqlite3','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks',
})
test_configs=configs('tests',{
    'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'br.com.iancfreitas.financeiro.tests',
    'GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Financeiro.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Financeiro',
    'BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    'OTHER_LDFLAGS':'$(inherited) -lsqlite3',
})
app_id=ident('appTarget')
project_id=ident('project')
proxy=obj('testProxy',f'{{ isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = Financeiro; }}')
dependency=obj('testDependency',f'{{ isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy}; }}')
obj('appTarget',f'{{ isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {sequence(app_phases)}; buildRules = (); dependencies = (); name = Financeiro; productName = Financeiro; productReference = {app_product}; productType = "com.apple.product-type.application"; }}')
test_id=obj('testTarget',f'{{ isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {sequence(test_phases)}; buildRules = (); dependencies = {sequence([dependency])}; name = FinanceiroTests; productName = FinanceiroTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test"; }}')
obj('project',f'{{ isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 16.0; }}; {test_id} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = pt_BR; hasScannedForEncodings = 0; knownRegions = (pt_BR, en, Base); mainGroup = {root_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {sequence([app_id,test_id])}; }}')
project_dir=ROOT/'Financeiro.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'+''.join(f'  {key} = {value};\n' for key,value in objects.items())+f' }};\n rootObject = {project_id};\n}}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="Financeiro.app" BlueprintName="Financeiro" ReferencedContainer="container:Financeiro.xcodeproj"/></BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_id}" BuildableName="FinanceiroTests.xctest" BlueprintName="FinanceiroTests" ReferencedContainer="container:Financeiro.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="Financeiro.app" BlueprintName="Financeiro" ReferencedContainer="container:Financeiro.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"/>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir=project_dir/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
(scheme_dir/'Financeiro.xcscheme').write_text(scheme)
print(f'Projeto gerado: {len(app_files)} fontes, {len(test_files)} arquivos de teste.')
