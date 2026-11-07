# frozen_string_literal: true

# Simulator-only arch pins for Patrol dev flavor (generic iOS Simulator build-for-testing).
module PatrolDevSimulatorArch
  ARCHS_KEY = 'ARCHS[sdk=iphonesimulator*]'
  EXCLUDED_KEY = 'EXCLUDED_ARCHS[sdk=iphonesimulator*]'
  ONLY_ACTIVE_KEY = 'ONLY_ACTIVE_ARCH[sdk=iphonesimulator*]'
  SDKROOT_KEY = 'SDKROOT[sdk=iphonesimulator*]'

  module_function

  def dev_configuration?(name)
    name.end_with?('-dev')
  end

  def apply_build_settings!(build_settings)
    build_settings['SDKROOT'] ||= 'iphoneos'
    build_settings[SDKROOT_KEY] = 'iphonesimulator'
    build_settings[ARCHS_KEY] = 'arm64'
    build_settings[EXCLUDED_KEY] = '$(inherited) arm64e i386 x86_64'
    build_settings[ONLY_ACTIVE_KEY] = 'YES'
  end

  def apply_to_native_target!(target)
    target.build_configurations.each do |cfg|
      next unless dev_configuration?(cfg.name)

      apply_build_settings!(cfg.build_settings)
    end
  end

  def apply_to_pods_project!(pods_project)
    pods_project.targets.each do |target|
      apply_to_native_target!(target)
    end
  end

  def apply_to_user_project!(user_project)
    %w[Runner RunnerUITests].each do |target_name|
      target = user_project.targets.find { |t| t.name == target_name }
      apply_to_native_target!(target) if target
    end

    user_project.build_configuration_list.build_configurations.each do |cfg|
      next unless dev_configuration?(cfg.name)

      apply_build_settings!(cfg.build_settings)
    end
  end
end
