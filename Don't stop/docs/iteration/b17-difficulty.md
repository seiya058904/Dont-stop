# B17 difficulty and actual barrage observations

Values below are exported from the live current configuration. Boss HP/armor, ordinary speed/damage and elite promotion rules were not increased in B17.

|Stage|Cap|Arrival seconds|Horde batch/floor|Ordinary extra HP|Hell HP axis|Light radius|Special / elite cap|
|---|---|---|---|---|---|---|---|
|30|20|1.5|-/-|1|1.0|264.96|-/-|
|31|65|0.2339|8/10|1.05|1.15|219.65|4/2|
|32|76|0.2102|10/13|1.06875|1.289|212.89|4/2|
|33|87|0.1898|12/15|1.0875|1.428|206.13|4/2|
|34|100|0.172|14/18|1.10625|1.567|194.3|4/2|
|35|113|0.1564|19/22|1.125|1.706|185.86|4/2|
|36|126|0.1425|21/25|1.14375|1.844|177.41|4/2|
|37|141|0.1302|26/30|1.1625|1.983|168.96|4/2|
|38|156|0.1191|32/36|1.18125|2.122|162.2|4/2|
|39|168|0.1118|36/40|1.2|2.261|155.44|4/2|
|40|24|1.4|-/-|1|2.4|148.68|-/-|

Meteor radius 56; live allowance 3; only legal visible candidates are admitted. A cap is not a promise of three simultaneous meteors. Fog starts visually at 30; Hell gameplay remains 31.

|Boss stage|Phase|Actual scheduled cycle|Requested / emitted in 22s|Emitted per second|
|---|---|---|---|---|
|10|1|charge, cleave, slam|68 / 68|3.09|
|10|2|charge, cleave, slam|42 / 42|1.91|
|10|3|charge, slam, shockwave|214 / 214|9.73|
|20|1|brood, lockdown, pulse|194 / 194|8.82|
|20|2|brood, lockdown, pulse|231 / 231|10.50|
|20|3|toxic_zone, root_shot, brood|240 / 240|10.91|
|30|1|dash, sweep, burst|162 / 162|7.36|
|30|2|dash, sweep, burst|123 / 123|5.59|
|30|3|cross_laser, burst, sweep, burst|315 / 315|14.32|
|40|1|dash, sweep, burst|210 / 210|9.55|
|40|2|burst, sweep, dash, cross, band|151 / 151|6.86|
|40|3|burst, cross_laser, burst, sweep, band|492 / 492|22.36|

Counts are phase-window deltas; the action dictionary in the raw record is cumulative. Controlled windows replenish HP and can carry an already issued warning/wave across phase transition. They prove scheduling/admission, not normal-health safe routes.

Ring opening uses abs(angle)<0.42 radians and rotates as a whole with each wave. Geometry checks at radius80 exceed the combined 24px hit threshold for 20..64 slots. Normal-health autonomous completion passed bosses10/20/30 and failed40; a human safe-route judgement is still required.

|Elite base role|Retained attack modifier|
|---|---|
|B01|ram_shockwave|
|B02|hive|
|B03|cross_beam|
|B04|ember_field|
|E01|sprint|
|E02|pack|
|E03|ram_shockwave|
|E04|double_charge|
|E05|burst|
|E06|cluster|
|E07|hive|
|E09|bulwark|
|E10|root_artillery|
|E11|fan|
|E12|ember_field|
|E13|double_root|
|E14|cross_beam|
|E15|lingering_poison|

Elite modifiers are source-table observations, not a fresh normal-health execution certificate for every elite. The existing B11Fairness attack contracts passed61 checks. No elite count increase was introduced.
