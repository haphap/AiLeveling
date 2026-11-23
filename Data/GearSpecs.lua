-- Forever specialization weights adapted from GearGuide (34697c4). See docs/SOURCES.json.
--[[MIT License

Copyright (c) 2026 cachila

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
local _,A=...

local function spec(key,tree,label,role,weights)
    return {key=key,tree=tree,label=label,role=role,weights=weights}
end

A.GearSpecs={
    WARRIOR={
        spec("arms",26,"武器","melee",{
            STRENGTH=1, EXPERTISE_RATING=1.4, HIT_RATING=1.1, CRIT_RATING=0.94, AGILITY=0.72, HASTE_RATING=0.64,
            ATTACK_POWER=0.45, ARMOR_PENETRATION_RATING=0.21, MAIN_DPS=7.32, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("fury",256,"狂暴","melee",{
            STRENGTH=1, EXPERTISE_RATING=1.69, HIT_RATING=1.15, CRIT_RATING=0.88, HASTE_RATING=0.87,
            AGILITY=0.68, ATTACK_POWER=0.45, ARMOR_PENETRATION_RATING=0.21, MAIN_DPS=4.38, OFF_DPS=1.77,
            STAMINA=0.25, ARMOR=0.01,
        }),
        spec("prot_warrior",257,"防战","tank",{
            STRENGTH=1, EXPERTISE_RATING=4, CRIT_RATING=0.75, HASTE_RATING=0.56, BLOCK_VALUE=0.53, AGILITY=0.47,
            ATTACK_POWER=0.44, ARMOR_PENETRATION_RATING=0.2, HIT_RATING=0.1, MAIN_DPS=2.57, STAMINA=0.6,
            ARMOR=0.05, DEFENSE_SKILL_RATING=0.4, DODGE_RATING=0.4, PARRY_RATING=0.3, BLOCK_RATING=0.2,
        }),
    },
    PALADIN={
        spec("retribution",184,"惩戒","melee",{
            STRENGTH=1, EXPERTISE_RATING=2.65, SPELL_POWER=1.9, CRIT_RATING=1.67, HASTE_RATING=1.62,
            INTELLECT=1.45, HOLY_DAMAGE_DONE=1.41, AGILITY=1.23, HIT_RATING=0.6, ATTACK_POWER=0.41,
            ARMOR_PENETRATION_RATING=0.1, MAIN_DPS=5.39, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("prot_paladin",267,"防骑","tank",{
            STRENGTH=0.4, EXPERTISE_RATING=5.7, SPELL_POWER=1, HOLY_DAMAGE_DONE=1, CRIT_RATING=1.97,
            BLOCK_RATING=1, HASTE_RATING=1.26, HIT_RATING=0.77, AGILITY=0.4, ATTACK_POWER=0.41, INTELLECT=0.09,
            ARMOR_PENETRATION_RATING=0.08, MANA_REGENERATION=0.02, MAIN_DPS=5.35, STAMINA=1, ARMOR=0.02,
            DEFENSE_SKILL_RATING=1, DODGE_RATING=1, PARRY_RATING=0.3,
        }),
        spec("holy_paladin",56,"奶骑","healer",{
            INTELLECT=1, MANA_REGENERATION=1.1, CRIT_RATING=0.9, HEALING=0.48, HASTE_RATING=0.33, SPIRIT=0.26,
            STAMINA=0.25, ARMOR=0.01,
        }),
    },
    PRIEST={
        spec("shadow",78,"暗牧","caster",{
            SPELL_POWER=1, SHADOW_DAMAGE_DONE=1, HIT_RATING=1.27, CRIT_RATING=0.92, HASTE_RATING=0.5,
            INTELLECT=0.27, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("discipline",613,"戒律","healer",{
            HEALING=1, HASTE_RATING=2.99, CRIT_RATING=1.21, INTELLECT=1.07, MANA_REGENERATION=0.42, SPIRIT=0.13,
            STAMINA=0.25, ARMOR=0.01,
        }),
        spec("holy_priest",594,"神牧","healer",{
            HEALING=1, HASTE_RATING=2.91, CRIT_RATING=0.9, INTELLECT=0.47, SPIRIT=0.28, MANA_REGENERATION=0.05,
            STAMINA=0.25, ARMOR=0.01,
        }),
    },
    DRUID={
        spec("balance",574,"鸟德","caster",{
            SPELL_POWER=1, HIT_RATING=1, HASTE_RATING=0.95, CRIT_RATING=0.7, ARCANE_DAMAGE_DONE=0.65,
            NATURE_DAMAGE_DONE=0.35, INTELLECT=0.26, MANA_REGENERATION=0.08, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("feral_cat",134,"猫德","melee",{
            AGILITY=1, STRENGTH=0.94, HIT_RATING=0.79, EXPERTISE_RATING=0.77, CRIT_RATING=0.75,
            HASTE_RATING=0.51, ATTACK_POWER=0.39, ARMOR_PENETRATION_RATING=0.13, MAIN_DPS=3.31, STAMINA=0.3,
            ARMOR=0.02,
        }),
        spec("feral_bear",134,"熊德","tank",{
            AGILITY=1, EXPERTISE_RATING=5.5, HIT_RATING=2.03, STRENGTH=1.61, CRIT_RATING=1.35, HASTE_RATING=0.8,
            ATTACK_POWER=0.73, ARMOR_PENETRATION_RATING=0.31, MAIN_DPS=5.6, STAMINA=0.6, ARMOR=0.05,
            DEFENSE_SKILL_RATING=0.4, DODGE_RATING=0.4,
        }),
        spec("resto_druid",573,"奶德","healer",{
            HEALING=1, HASTE_RATING=2.28, CRIT_RATING=0.8, SPIRIT=0.35, MANA_REGENERATION=0.2, INTELLECT=0.16,
            STAMINA=0.25, ARMOR=0.01,
        }),
    },
    SHAMAN={
        spec("elemental",375,"元素","caster",{
            SPELL_POWER=1, HASTE_RATING=1.15, HIT_RATING=1.14, CRIT_RATING=0.72, NATURE_DAMAGE_DONE=0.87,
            FIRE_DAMAGE_DONE=0.11, INTELLECT=0.33, MANA_REGENERATION=0.02, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("enhancement",373,"增强","melee",{
            STRENGTH=1, EXPERTISE_RATING=1.8, HASTE_RATING=1.19, CRIT_RATING=1.08, HIT_RATING=0.95,
            INTELLECT=0.89, AGILITY=0.72, SPELL_POWER=0.65, ATTACK_POWER=0.45, NATURE_DAMAGE_DONE=0.29,
            ARMOR_PENETRATION_RATING=0.18, MAIN_DPS=6.23, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("resto_shaman",374,"奶萨","healer",{
            HEALING=1, HASTE_RATING=2.2, INTELLECT=1.21, CRIT_RATING=0.79, MANA_REGENERATION=0.35, STAMINA=0.25,
            ARMOR=0.01,
        }),
    },
    HUNTER={
        spec("beast_mastery",50,"兽王","ranged",{
            AGILITY=1, CRIT_RATING=0.83, HIT_RATING=0.84, EXPERTISE_RATING=0.63, HASTE_RATING=0.57,
            INTELLECT=0.49, RANGED_ATTACK_POWER=0.32, ATTACK_POWER=0.37, ARMOR_PENETRATION_RATING=0.13,
            MANA_REGENERATION=0.13, STRENGTH=0.05, RANGED_DPS=3.29, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("marksmanship",163,"射击","ranged",{
            AGILITY=1, CRIT_RATING=0.84, HIT_RATING=0.67, HASTE_RATING=0.53, INTELLECT=0.49,
            RANGED_ATTACK_POWER=0.32, ATTACK_POWER=0.37, EXPERTISE_RATING=0.16, ARMOR_PENETRATION_RATING=0.13,
            MANA_REGENERATION=0.11, STRENGTH=0.06, RANGED_DPS=3.39, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("survival",51,"生存","ranged",{
            AGILITY=1, CRIT_RATING=0.8, HIT_RATING=0.8, EXPERTISE_RATING=0.59, INTELLECT=0.54,
            RANGED_ATTACK_POWER=0.21, MANA_REGENERATION=0.2, STRENGTH=0.18, ATTACK_POWER=0.38,
            ARMOR_PENETRATION_RATING=0.14, HASTE_RATING=0.07, RANGED_DPS=1.88, MAIN_DPS=1, STAMINA=0.25,
            ARMOR=0.01,
        }),
    },
    ROGUE={
        spec("assassination",253,"奇袭","melee",{
            AGILITY=1, EXPERTISE_RATING=1.34, CRIT_RATING=0.94, HIT_RATING=0.9, HASTE_RATING=0.61,
            STRENGTH=0.53, ATTACK_POWER=0.48, ARMOR_PENETRATION_RATING=0.21, MAIN_DPS=3.83, OFF_DPS=1.5,
            STAMINA=0.25, ARMOR=0.01,
        }),
        spec("combat",38,"战斗","melee",{
            AGILITY=1, EXPERTISE_RATING=1.34, HIT_RATING=1.04, CRIT_RATING=0.79, HASTE_RATING=0.73,
            STRENGTH=0.59, ATTACK_POWER=0.54, ARMOR_PENETRATION_RATING=0.2, MAIN_DPS=5.31, OFF_DPS=1.5,
            STAMINA=0.25, ARMOR=0.01,
        }),
        spec("subtlety",39,"敏锐","melee",{
            AGILITY=1, EXPERTISE_RATING=1.27, HIT_RATING=0.96, CRIT_RATING=0.84, HASTE_RATING=0.66,
            STRENGTH=0.57, ATTACK_POWER=0.52, ARMOR_PENETRATION_RATING=0.16, MAIN_DPS=5.28, OFF_DPS=0.96,
            STAMINA=0.25, ARMOR=0.01,
        }),
    },
    MAGE={
        spec("arcane",237,"奥法","caster",{
            SPELL_POWER=1, ARCANE_DAMAGE_DONE=0.98, HASTE_RATING=1.44, HIT_RATING=1.4, INTELLECT=1.01,
            CRIT_RATING=0.73, MANA_REGENERATION=0.29, SPIRIT=0.19, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("fire",8,"火法","caster",{
            SPELL_POWER=1, FIRE_DAMAGE_DONE=0.96, ARCANE_DAMAGE_DONE=0.04, HIT_RATING=1.55, CRIT_RATING=0.77,
            HASTE_RATING=0.45, INTELLECT=0.38, MANA_REGENERATION=0.12, SPIRIT=0.05, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("frost",6,"冰法","caster",{
            SPELL_POWER=1, FROST_DAMAGE_DONE=0.99, HIT_RATING=1.36, HASTE_RATING=1.16, CRIT_RATING=0.65,
            INTELLECT=0.18, STAMINA=0.25, ARMOR=0.01,
        }),
    },
    WARLOCK={
        spec("affliction",355,"痛苦","caster",{
            SPELL_POWER=1, SHADOW_DAMAGE_DONE=0.91, FIRE_DAMAGE_DONE=0.09, HASTE_RATING=0.98, HIT_RATING=0.83,
            CRIT_RATING=0.78, INTELLECT=0.31, MANA_REGENERATION=0.08, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("demonology",354,"恶魔","caster",{
            SPELL_POWER=1, SHADOW_DAMAGE_DONE=0.81, FIRE_DAMAGE_DONE=0.17, HASTE_RATING=1.35, HIT_RATING=1.31,
            CRIT_RATING=0.8, INTELLECT=0.33, MANA_REGENERATION=0.14, STAMINA=0.25, ARMOR=0.01,
        }),
        spec("destruction",593,"毁灭","caster",{
            SPELL_POWER=1, SHADOW_DAMAGE_DONE=0.8, FIRE_DAMAGE_DONE=0.2, HIT_RATING=1.11, CRIT_RATING=0.83,
            HASTE_RATING=0.83, INTELLECT=0.4, MANA_REGENERATION=0.18, STAMINA=0.25, ARMOR=0.01,
        }),
    },
}
