-- UTF-8 source; native copy is GBK. Only this adapter interprets native handlers.
-- These are effect families, not learned technique IDs or names. Every tier/copy
-- inherits its effect from FUNCNAME/COMMENT/SKILLID and scope/power from TARGET/OPTION.
local D={}
local EFFECT={
 TECH_NormalAttack={'ATTACK','physical','damage'},
 TECH_NormalGuard={'GUARD','support','defend',stance=true},
 TECH_ContinuationAttack={'P_RENZOKU','physical','damage',repeatHits=true},
 TECH_Parameter={'P_PARAMETER','physical','damage',stance=true},
 TECH_SpiracleShot={'P_SPIRACLESHOT','physical','damage',randomHits=true,absoluteDD=true},
 TECH_GuardBreak={'P_GUARDBREAK','physical','guard_break'},
 TECH_Forcecut={'P_FORCECUT','physical','drain_mp'},
 TECH_RandomShot={'P_RANDOMSHOT','physical','damage',randomHits=true},
 TECH_PanicAttack={'P_PANIC','physical','status',status='confuse'},
 TECH_Attack_Magic={'P_MAGIC','magic','damage',elemental=true},
 TECH_StatusAttack={'M_STATUSATTACK','physical','status'},
 TECH_StatusChange={'P_STATUSCHANGE','magic','control'},
 TECH_BloodAttack={'M_BLOODATTACK','physical','drain_hp'},
 TECH_Death={'M_DEATH','magic','death'},
 TECH_Assassin={'P_ASSASSIN','physical','death'},
 TECH_EarthQuake={'M_EARTHQUAKE','physical','damage'},
 TECH_AttackAll={'ATTACKALL','physical','damage',sideHits=true},
 TECH_Ranbu={'RANBU','physical','damage',sideHits=true},
 TECH_Heal_Magic={'P_HEAL','support','heal'},
 TECH_LpRecovery={'P_LP_RECOVERY','support','regen'},
 TECH_Revive={'P_REVIVE','support','revive'},
 TECH_StatusRecover={'P_STATUSRECOVER','support','cleanse'},
 TECH_BodyGuard={'P_BODYGUARD','support','protect',stance=true,prepaid=true},
 TECH_Consentration={'P_CONSENTRATION','support','self_heal',stance=true},
 TECH_Reflection_Physics={'P_REFLECTION_PHYSICS','support','barrier',barrier='physical',statusKey='Õ½Êô_¹¥·´'},
 TECH_Reflection_Magic={'P_REFLECTION_MAGIC','support','barrier',barrier='magic',statusKey='Õ½Êô_Ä§·´'},
 TECH_Absorb_Physics={'P_ABSORB_PHYSICS','support','barrier',barrier='physical',statusKey='Õ½Êô_¹¥Îü'},
 TECH_Absorb_Magic={'P_ABSORB_MAGIC','support','barrier',barrier='magic',statusKey='Õ½Êô_Ä§Îü'},
 TECH_Ineffective_Physics={'P_INEFFECTIVE_PHYSICS','support','barrier',barrier='physical',statusKey='Õ½Êô_¹¥ÎŞ'},
 TECH_Ineffective_Magic={'P_INEFFECTIVE_MAGIC','support','barrier',barrier='magic',statusKey='Õ½Êô_Ä§ÎŞ'},
 TECH_MagicGuard={'P_MAGICGARD','support','defend',stance=true},
 TECH_SpecialGuard={'P_SPECIALGARD','support','defend',stance=true},
 TECH_Mikawashi={'P_DODGE','support','defend',stance=true},
 TECH_CrossCounter={'P_CROSSCOUNTER','support','defend',stance=true},
 -- Resource spending, equipment destruction and field changes need an explicit policy.
 TECH_GoldAttack={'M_GOLDATTACK','manual','money'},
 TECH_EquipBreakAttack={'M_BREAKATTACK','manual','equipment'},
 TECH_EnergyDrain={'M_ENERGYDRAIN','manual','experience'},
 TECH_Treat_Type={'P_TREAT_TYPE','manual','field'},
}
local STATUS={'poison','sleep','stone','drunk','confuse','forget'}
local STATUS_KEY={poison='Õ½Êô_¶¾',sleep='Õ½Êô_Ë¯',stone='Õ½Êô_Ê¯',drunk='Õ½Êô_×í',confuse='Õ½Êô_ÂÒ',forget='Õ½Êô_Íü'}
local RESIST={poison='CHAR_¿¹¶¾',sleep='CHAR_¿¹Ë¯',stone='CHAR_¿¹Ê¯',drunk='CHAR_¿¹×í',confuse='CHAR_¿¹ÂÒ',forget='CHAR_¿¹Íü'}
local function flag(value,bit) return math.floor(value/bit)%2==1 end
function D.describe(t)
 local e=EFFECT[t.fn];if not e then return nil end
 local command=CONST.BATTLE_COM['BATTLE_COM_'..e[1]];if not command then return nil end
 t.command=command;t.category=e[2];t.effect=e[3]
 for k,v in pairs(e) do if type(k)=='string' then t[k]=v end end
 t.power={};for k,v in t.option:gmatch('([%w_]+):([%d%.%-]+)') do t.power[k]=tonumber(v) end
 t.scope=flag(t.target,256) and 'all' or (flag(t.target,128) and 'cross' or 'single')
 t.ranged=not flag(t.target,1024)
 t.canSelf=flag(t.target,8);t.canAlly=flag(t.target,16);t.canEnemy=flag(t.target,32)
 t.canDead=flag(t.target,2);t.canLive=flag(t.target,4)
 if t.effect=='self_heal' or t.effect=='defend' then t.scope='self' end
 if t.randomHits then t.spread='random' elseif t.sideHits then t.spread='side' end
 -- COMMENT preserves the original family in generated copies; SKILLID can be a
 -- new catalog group (e.g. 4110). Native families also use short group IDs 19..30.
 local family=t.family or t.skill
 local magicFamily=family>=130019 and family<=130030 and family-130000 or t.skill
 if t.elemental and magicFamily>=19 and magicFamily<=30 then t.element=(magicFamily-19)%4+1 end
 local status=t.status
 if t.effect=='status' and family>=107500 and family<=108000 and family%100==0 then
  status=STATUS[(family-107500)/100+1]
 elseif t.effect=='status' and family==3007190 then status='poison'
 elseif t.effect=='status' and t.skill>=75 and t.skill<=80 then status=STATUS[t.skill-74]
 elseif t.effect=='control' then
  local controlFamily=family>=130032 and family<=130049 and family-130000 or t.skill
  if controlFamily>=32 and controlFamily<=49 then status=STATUS[(controlFamily-32)%6+1] end
 end
 if status then t.statusKey=STATUS_KEY[status];t.resistKey=RESIST[status] end
 t.minHits=math.max(1,t.power.AN or 1);t.maxHits=math.max(t.minHits,t.power.AM or t.minHits)
 t.damageFactor=t.absoluteDD and (t.power.DD or 100)/100 or (1+(t.power.DD or t.power.TR or 0)/100)
 t.defensePenalty=(t.power.DR or 0)<0 or (t.power.MR or 0)<0
 return t
end
return D
