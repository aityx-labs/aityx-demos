# Scoring

At the end of each round the app sends each robot's `died` (0 if it
survived) and `damage` to aityx's `/v1/systemone` with
[assets/models/scoring.json](../roborules_app/assets/models/scoring.json),
the app's asset, as the decision
([AityxBattleApi.score](../roborules_app/lib/battle/api.dart)):

- **Survival**: 50 for each robot that died before it (`survival_points`).
- **Last survivor**: 10 per enemy for the last robot standing
  (`last_survivor_points`).
- **Bullet damage**: 1 per point dealt.
- **Total**, and the round's **winner**, the highest total.

The app adds the rounds up; **Results** ranks the robots by total, with
survival, the survivor bonus, bullet damage and the rounds won ("1sts").
Robocode's ram and kill bonuses are left out.
