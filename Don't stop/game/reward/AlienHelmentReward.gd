extends BaseReward

func onRewardStart():
	if count <= 4: PlayerData.player_hp_max += 3

func onCountChange():
	if count <= 4: PlayerData.player_hp_max += 3
