# Adds Engine/platform/ios/ios_touchpad.mm (from ags-touchpad.patch) to the
# AGS_iOS framework target of AGS's Xcode project.
require 'xcodeproj'

project = Xcodeproj::Project.open(ARGV[0])
target = project.targets.find { |t| t.name == 'AGS_iOS' } or abort 'no AGS_iOS target'
ref = project.files.find { |f| f.path == 'acplios.cpp' } or abort 'no acplios.cpp'
mm = ref.parent.new_reference('ios_touchpad.mm')
target.add_file_references([mm])
project.save
puts "added #{mm.real_path}"
