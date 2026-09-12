extends BaseReward

func onRewardStart():
	PlayerData.player_hp_max += 3

func onCountChange():
	PlayerData.player_hp_max += 3
