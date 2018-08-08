local rule = Rule.eval

local devs = {
  kitchen={lamp=55, sensor=56},
  bedroom={lamp=66, sensor=67},
  hall={lamp=76, door=77, sensor=78}}

Util.defvars(devs)
Util.reverseMapDef(devs)

rule("@10:00 => kitchen.lamp:on")
rule("@10:00 & wday('mon-fr') => kitchen.lamp:on")
rule("@10:00 & wday('mon-fr') & $Presence=='Home' => kitchen.lamp:on")
rule("@10:00 & wday('mon-fr') & $Presence=='Home' => kitchen.lamp:on; log('Turning on kitchen lamp!')")

rule("@sunrise+15 => kitchen.lamp:off")
rule("@sunset-15  => kitchen.lamp:on")

rule("lamps={kitchen.lamp,bedroom.lamp,hall.lamp}")
rule("@sunrise+15 => lamps:off")
rule("@sunset-15  => lamps:on")

rule("@10:00 => kitchen.lamp:on")
rule("@10:00 => kitchen.lamp:on")