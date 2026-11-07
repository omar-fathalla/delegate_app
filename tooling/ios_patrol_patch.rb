#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, 'ios', 'Runner.xcodeproj')
FEAT = File.join(ROOT, 'tmp_feat_ios', 'Runner.xcodeproj')
SPM = 'Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage'

unless File.exist?(File.join(FEAT, 'project.pbxproj'))
  require 'fileutils'
  FileUtils.mkdir_p(FEAT)
  IO.popen(['git', '-C', ROOT, 'show', 'origin/feat/ios-dev-flavor:ios/Runner.xcodeproj/project.pbxproj']) do |io|
    File.write(File.join(FEAT, 'project.pbxproj'), io.read)
  end
end

project = Xcodeproj::Project.open(PROJECT)
feat = Xcodeproj::Project.open(FEAT)

def flutter_ref(project, name)
  g = project.main_group.find_subpath('Flutter', false) || project.main_group.new_group('Flutter', 'Flutter')
  g.files.find { |f| f.path == "Flutter/#{name}" } || g.new_file("Flutter/#{name}")
end

DEV_XC = {
  'Debug-dev' => flutter_ref(project, 'Debug-dev.xcconfig'),
  'Release-dev' => flutter_ref(project, 'Release-dev.xcconfig'),
  'Profile-dev' => flutter_ref(project, 'Profile-dev.xcconfig'),
}.freeze

def pods_runner_ui_tests_xcconfig(project, name)
  slug = name.downcase
  project.files.find { |f| f.name == "Pods-RunnerUITests.#{slug}.xcconfig" }
end

def apply_runner_ui_tests_debug_dev_arch!(cfg)
  return unless cfg.name == 'Debug-dev'

  cfg.build_settings['ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  cfg.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = '$(inherited) arm64e i386 x86_64'
  cfg.build_settings['ONLY_ACTIVE_ARCH[sdk=iphonesimulator*]'] = 'YES'
  cfg.build_settings['SDKROOT[sdk=iphonesimulator*]'] = 'iphonesimulator'
end

def append_dev_configs(project, feat_list, dest_list, runner: false, ui: false, unit: false)
  %w[Debug-dev Release-dev Profile-dev].each do |name|
    next if dest_list.build_configurations.any? { |c| c.name == name }

    src = feat_list.build_configurations.find { |c| c.name == name }
    next unless src

    cfg = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    cfg.name = name
    cfg.build_settings = src.build_settings.transform_values { |v| v.is_a?(Array) ? v.dup : v }
    cfg.base_configuration_reference = DEV_XC[name] if runner
    if ui
      pods_ref = pods_runner_ui_tests_xcconfig(project, name)
      cfg.base_configuration_reference = pods_ref if pods_ref
      cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tashil.delegate.dev.RunnerUITests'
      cfg.build_settings['PRODUCT_NAME'] = 'RunnerUITests'
      cfg.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
      cfg.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
      cfg.build_settings['SWIFT_VERSION'] = '5.0'
      cfg.build_settings['TEST_TARGET_NAME'] = 'Runner'
      cfg.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
      cfg.build_settings.delete('BUNDLE_LOADER')
      cfg.build_settings.delete('TEST_HOST')
      apply_runner_ui_tests_debug_dev_arch!(cfg)
    end
    cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tashil.delegate.dev.RunnerTests' if unit
    dest_list.build_configurations << cfg
  end
end

append_dev_configs(project, feat.build_configuration_list, project.build_configuration_list)

feat.targets.each do |ft|
  t = project.targets.find { |x| x.name == ft.name }
  next unless t

  append_dev_configs(
    project,
    ft.build_configuration_list,
    t.build_configuration_list,
    runner: ft.name == 'Runner',
    ui: ft.name == 'RunnerUITests',
    unit: ft.name == 'RunnerTests',
  )
end

runner = project.targets.find { |t| t.name == 'Runner' }

unless runner.shell_script_build_phases.any? { |p| p.name&.include?('Firebase config check') }
  check = runner.new_shell_script_build_phase('Tashil Firebase config check')
  check.shell_script = "/bin/sh \"${SRCROOT}/scripts/firebase_config.sh\" check\n"
  runner.build_phases.insert(1, check)
end

unless runner.shell_script_build_phases.any? { |p| p.name&.include?('Firebase config install') }
  install = runner.new_shell_script_build_phase('Tashil Firebase config install')
  install.shell_script = "/bin/sh \"${SRCROOT}/scripts/firebase_config.sh\" install\n"
  idx = runner.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
  runner.build_phases.insert(idx + 1, install) if idx
end

unless runner.shell_script_build_phases.any? { |p| p.name&.include?('dev upload guard') }
  guard = runner.new_shell_script_build_phase('Tashil dev upload guard')
  guard.shell_script = "/bin/sh \"${SRCROOT}/scripts/dev_upload_guard.sh\"\n"
  idx = runner.build_phases.index do |p|
    p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) &&
      p.name&.include?('Firebase config install')
  end
  runner.build_phases.insert(idx + 1, guard) if idx
end

package_ref = project.root_object.package_references&.find { |r| r.path&.include?('FlutterGeneratedPluginSwiftPackage') }
unless package_ref
  ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  ref.relative_path = SPM
  project.root_object.package_references ||= []
  project.root_object.package_references << ref
  package_ref = ref
end

def add_spm(project, target, package_ref)
  return if target.package_product_dependencies.any? { |d| d.product_name == 'FlutterGeneratedPluginSwiftPackage' }

  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = package_ref
  dep.product_name = 'FlutterGeneratedPluginSwiftPackage'
  target.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  target.frameworks_build_phase.files << bf
end

add_spm(project, runner, package_ref)

unless project.targets.any? { |t| t.name == 'RunnerUITests' }
  grp = project.main_group.new_group('RunnerUITests', 'RunnerUITests')
  ui_file = grp.new_file('RunnerUITests.m')

  ui = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '15.0')
  ui.product_reference.path = 'RunnerUITests.xctest'
  ui.source_build_phase.add_file_reference(ui_file)
  ui.add_dependency(runner)

  %w[Debug Release Profile].each do |base|
    rc = runner.build_configuration_list.build_configurations.find { |c| c.name == base }
    uc = ui.build_configuration_list.build_configurations.find { |c| c.name == base }
    uc.build_settings.merge!(
      'CODE_SIGN_STYLE' => 'Automatic',
      'CURRENT_PROJECT_VERSION' => '1',
      'DEVELOPMENT_TEAM' => rc.build_settings['DEVELOPMENT_TEAM'],
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
      'MARKETING_VERSION' => '1.0',
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.tashil.delegate.RunnerUITests',
      'SWIFT_VERSION' => '5.0',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'TEST_TARGET_NAME' => 'Runner',
    )
  end

  append_dev_configs(project, feat.targets.find { |t| t.name == 'Runner' }.build_configuration_list,
                   ui.build_configuration_list, ui: true)

  project.products_group.children << ui.product_reference

  project.targets << ui unless project.targets.include?(ui)

  attrs = project.root_object.attributes['TargetAttributes'] ||= {}
  attrs[ui.uuid] ||= {}
  attrs[ui.uuid]['TestTargetID'] = runner.uuid
end

PATROL_OTHER_CFLAGS = [
  '$(inherited)',
  '-fmodule-map-file="${PODS_ROOT}/../.symlinks/plugins/patrol/darwin/patrol/Sources/patrol/include/module.modulemap"',
].freeze
PATROL_HEADER_SEARCH_PATHS = [
  '$(inherited)',
  '${PODS_ROOT}/../.symlinks/plugins/patrol/darwin/patrol/Sources/patrol/include',
  '${PODS_CONFIGURATION_BUILD_DIR}/patrol/patrol.framework/Headers',
].freeze
PATROL_SWIFT_INCLUDE_PATHS = ['$(inherited)', '${PODS_CONFIGURATION_BUILD_DIR}/patrol'].freeze

ui_target = project.targets.find { |t| t.name == 'RunnerUITests' }
if ui_target
  ui_target.build_configurations.each do |cfg|
    cfg.build_settings['SWIFT_VERSION'] = '5.0'
    cfg.build_settings['OTHER_CFLAGS'] = PATROL_OTHER_CFLAGS
    cfg.build_settings['HEADER_SEARCH_PATHS'] = PATROL_HEADER_SEARCH_PATHS
    cfg.build_settings['SWIFT_INCLUDE_PATHS'] = PATROL_SWIFT_INCLUDE_PATHS
    if %w[Debug-dev Release-dev Profile-dev].include?(cfg.name)
      pods_ref = pods_runner_ui_tests_xcconfig(project, cfg.name)
      cfg.base_configuration_reference = pods_ref if pods_ref
    end
    apply_runner_ui_tests_debug_dev_arch!(cfg)
  end

  unless ui_target.shell_script_build_phases.any? { |ph| ph.name == 'Patrol framework build order' }
    phase = ui_target.new_shell_script_build_phase('Patrol framework build order')
    phase.shell_script = "# Wait for patrol.framework before compiling RunnerUITests.m (@import patrol).\n"
    phase.input_paths = ['${PODS_CONFIGURATION_BUILD_DIR}/patrol/patrol.framework/Modules/module.modulemap']
    sources_idx = ui_target.build_phases.index { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
    ui_target.build_phases.insert(sources_idx, phase) if sources_idx
  end
end

project.save
puts 'ios_patrol_patch: OK'
