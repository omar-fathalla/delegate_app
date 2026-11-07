# frozen_string_literal: true

# RunnerUITests: lean patrol pod only + reliable @import patrol (see Podfile).
require_relative 'patrol_dev_simulator_arch'

module PatrolRunnerUiTestsPostInstall
  PATROL_HEADERS = [
    '$(inherited)',
    '${PODS_ROOT}/../.symlinks/plugins/patrol/darwin/patrol/Sources/patrol/include',
    '${PODS_CONFIGURATION_BUILD_DIR}/patrol/patrol.framework/Headers',
  ].freeze
  PATROL_SWIFT_INCLUDE_PATHS = ['$(inherited)', '${PODS_CONFIGURATION_BUILD_DIR}/patrol'].freeze

  module_function

  # Plugin source map uses umbrella "patrol.h" (on HEADER_SEARCH_PATHS). CocoaPods
  # Target Support Files/patrol/patrol.modulemap references patrol-umbrella.h, which
  # is not visible during RunnerUITests ScanDependencies → @import patrol fails.
  PATROL_SOURCE_MODULEMAP = '${PODS_ROOT}/../.symlinks/plugins/patrol/darwin/patrol/Sources/patrol/include/module.modulemap'.freeze

  def patrol_module_map_flag(pods_root)
    symlink = File.expand_path('../.symlinks/plugins/patrol/darwin/patrol/Sources/patrol/include/module.modulemap', pods_root)
    return %(-fmodule-map-file="#{PATROL_SOURCE_MODULEMAP}") if File.exist?(symlink)

    generated = File.join(pods_root, 'Target Support Files/patrol/patrol.modulemap')
    return %(-fmodule-map-file="${PODS_ROOT}/Target Support Files/patrol/patrol.modulemap") if File.exist?(generated)

    nil
  end

  def apply!(installer)
    pods_project = installer.pods_project
    patrol_target = pods_project.targets.find { |t| t.name == 'patrol' }
    pods_root = installer.sandbox.root

    installer.aggregate_targets.map(&:user_project).uniq.compact.each do |user_project|
      ui_target = user_project.targets.find { |t| t.name == 'RunnerUITests' }
      next unless ui_target

      module_flag = patrol_module_map_flag(pods_root)
      other_cflags = ['$(inherited)', module_flag].compact

      ui_target.build_configurations.each do |config|
        config.build_settings['SWIFT_VERSION'] = '5.0'
        config.build_settings['OTHER_CFLAGS'] = other_cflags
        config.build_settings['HEADER_SEARCH_PATHS'] = PATROL_HEADERS
        config.build_settings['SWIFT_INCLUDE_PATHS'] = PATROL_SWIFT_INCLUDE_PATHS
        PatrolDevSimulatorArch.apply_build_settings!(config.build_settings) if PatrolDevSimulatorArch.dev_configuration?(config.name)
      end

      ensure_patrol_build_order_script!(ui_target)
      add_remote_target_dependency(user_project, ui_target, pods_project, patrol_target) if patrol_target

      user_project.save
    end
  end

  def ensure_patrol_build_order_script!(ui_target)
    return if ui_target.shell_script_build_phases.any? { |ph| ph.name == 'Patrol framework build order' }

    phase = ui_target.new_shell_script_build_phase('Patrol framework build order')
    phase.shell_script = "# Wait for patrol.framework before compiling RunnerUITests.m (@import patrol).\n"
    phase.input_paths = ['${PODS_CONFIGURATION_BUILD_DIR}/patrol/patrol.framework/Modules/module.modulemap']
    sources_idx = ui_target.build_phases.index { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
    ui_target.build_phases.insert(sources_idx, phase) if sources_idx
  end

  def add_remote_target_dependency(user_project, user_target, pods_project, pods_target)
    return unless pods_target

    remote_name = pods_target.name
    return if user_target.dependencies.any? { |d| d.target_proxy&.remote_info == remote_name }

    pods_project_ref = user_project.files.find { |f| f.path&.end_with?('Pods.xcodeproj') }
    unless pods_project_ref
      pods_project_ref = user_project.new(Xcodeproj::Project::Object::PBXFileReference)
      pods_project_ref.name = 'Pods.xcodeproj'
      pods_project_ref.path = 'Pods/Pods.xcodeproj'
      pods_project_ref.last_known_file_type = 'wrapper.pb-project'
      pods_project_ref.source_tree = 'SOURCE_ROOT'
      user_project.main_group.children << pods_project_ref
    end

    proxy = user_project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
    proxy.container_portal = pods_project_ref.uuid
    proxy.proxy_type = '2'
    proxy.remote_global_id_string = pods_target.uuid
    proxy.remote_info = remote_name

    dep = user_project.new(Xcodeproj::Project::Object::PBXTargetDependency)
    dep.target = nil
    dep.target_proxy = proxy
    dep.name = remote_name
    user_target.dependencies << dep
  end
end
