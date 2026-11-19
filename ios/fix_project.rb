# Brings AGS's iOS Xcode project in line with the engine sources of the tag
# being built (the project isn't maintained upstream and lags behind files
# that moved), and adds Engine/platform/ios/ios_touchpad.mm from
# ags-touchpad.patch.
#
#   ruby fix_project.rb <ags checkout>
require 'xcodeproj'

ags = File.expand_path(ARGV[0])
project = Xcodeproj::Project.open(File.join(ags, 'iOS/xcode/ags/AGS.xcodeproj'))
engine = project.targets.find { |t| t.name == 'AGS_iOS' } or abort 'no AGS_iOS target'
vendor = project.targets.find { |t| t.name == 'AGS_ThirdParty_iOS' } or abort 'no AGS_ThirdParty_iOS target'

def rel(ags, ref)
  ref.real_path.to_s.sub("#{ags}/", '')
end

# 1. Drop sources that no longer exist, or that CMake no longer compiles.
OBSOLETE = %w[
  Common/game/room_file_deprecated.cpp
  Common/libsrc/freetype-2.1.3/src/psnames/psnames.c
].freeze
[engine, vendor].each do |t|
  t.source_build_phase.files.dup.each do |bf|
    ref = bf.file_ref
    next unless ref
    path = rel(ags, ref)
    next if path.start_with?('libsrc/') # downloaded libraries are checked below
    if !File.exist?(ref.real_path) || OBSOLETE.include?(path)
      puts "- #{t.name}: #{path}"
      t.source_build_phase.remove_build_file(bf)
    end
  end
end

# 2. Add what CMake builds and the project lacks.
ADD_ENGINE = %w[
  Common/data/assetmanager.cpp
  Common/data/data_ext.cpp
  Common/data/data_helpers.cpp
  Common/data/multifilelib.cpp
  Common/data/tra_file.cpp
  Common/game/roomdata.cpp
  Common/gfx/image_bmp.cpp
  Common/gfx/image_pcx.cpp
  Common/gfx/image_png.cpp
  Common/gfx/sprite_data_fmt.cpp
  Common/gui/guitextbasedcontrol.cpp
  Engine/ac/utils_script.cpp
  Engine/platform/ios/ios_touchpad.mm
].freeze
ADD_VENDOR = %w[
  Common/libsrc/freetype-2.1.3/src/psnames/psmodule.c
  libsrc/miniz_ex/miniz_ex.c
  libsrc/stb/stb_image.c
].freeze

group = project.main_group.find_subpath('Sync', true)
{ engine => ADD_ENGINE, vendor => ADD_VENDOR }.each do |t, list|
  have = t.source_build_phase.files.map { |bf| bf.file_ref && rel(ags, bf.file_ref) }
  list.each do |path|
    abort "missing #{path}" unless File.exist?(File.join(ags, path))
    next if have.include?(path)
    ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
    ref.path = "../../../#{path}" # from iOS/xcode/ags
    ref.source_tree = 'SOURCE_ROOT'
    ref.set_last_known_file_type
    group << ref
    t.add_file_references([ref])
    puts "+ #{t.name}: #{path}"
  end
end

# 3. Header paths the new files need.
[engine, vendor].each do |t|
  t.build_configurations.each do |c|
    hsp = Array(c.build_settings['HEADER_SEARCH_PATHS'] || '$(inherited)')
    %w[Common Engine libsrc/miniz libsrc/miniz_ex libsrc/stb].each do |d|
      q = "\"${SOURCE_ROOT}/../../../#{d}\""
      hsp << q unless hsp.include?(q)
    end
    c.build_settings['HEADER_SEARCH_PATHS'] = hsp
  end
end

project.save
