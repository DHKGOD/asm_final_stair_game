#413422447王詠弘 412262565林秉翰 413262641 葉書維
#Mars 設定 Width 8, Height 8, Base address $gp
.data
    #顯示設定
    displayAddress: .word 0x10008000
    screenWidth:    .word 64         # 螢幕寬度 64 
    screenHeight:   .word 32         # 螢幕高度 32 

    #顏色
    # 0x00RRGGBB
    colorBG:        .word 0x000000   # 黑色背景
    colorPlayer:    .word 0xFFFF00   # 黃色玩家
    colorPlat:      .word 0x00FF00   # 綠色樓梯
    colorHP:        .word 0xFF0000   # 紅色血條
    colorItem:      .word 0x00FFFF   # 青色星星
    colorScore:     .word 0x0000FF   # 藍色下方積分條
    
    #遊戲變數
    playerX:        .word 32         # 玩家 X 座標
    playerY:        .word 10         # 玩家 Y 座標
    hp:             .word 16         # 生命值滿血16
    score:          .word 0          # 目前藍色星星能量條
    totalScore:     .word 0          # 遊戲總分
    frameCounter:   .word 0          # 幀數計數器 (用來控制速度)

    #樓梯陣列 螢幕最多八個樓梯
    # platCount: 總共有 8 個樓梯
    platCount:      .word 8
    # platX: 每個樓梯的 X 座標
    platX:          .word 10, 50, 30, 5, 45, 20, 55, 15
    # platY: 每個樓梯的 Y 座標
    platY:          .word 20, 24, 28, 32, 36, 40, 44, 48
    # platItem: 每個樓梯上有沒有加分物 (0=沒有, 1=有)
    platItem:       .word 0, 1, 0, 0, 1, 0, 0, 0

    #樓梯 Stack
    platStack:      .space 400    
    stackPtr:       .word 0          # 堆疊指標 (最上層)
    lastIdx:        .word -1         # 紀錄上一次踩到的樓梯編號

    #文字訊息區
    str_start:      .asciiz "Game Start Have Fun\n"
    str_hp:         .asciiz "HP: "
    str_score:      .asciiz " Total: "
    str_newline:    .asciiz "\n"
    str_item:       .asciiz "Star! +500 pts.\n"
    str_levelup:    .asciiz ">>> Energy Full! HP +4 <<<\n"
    str_respawn:    .asciiz "Ouch! Big Damage (-4 HP).\n"
    str_gameover:   .asciiz "\nGame Over! Score: "
    str_paused:     .asciiz "PAUSED. Press 'p' to resume.\n"
    str_resumed:    .asciiz "RESUMED.\n"

#程式碼區
.text
.globl main


main:
    #印歡迎訊息
    li $v0, 4              
    la $a0, str_start       
    syscall

    #初始化變數
    li $t0, 32
    sw $t0, playerX         # 玩家初始 X = 32
    li $t0, 5
    sw $t0, playerY         # 玩家初始 Y = 5
    li $t0, 16
    sw $t0, hp              # 初始 HP = 16
    sw $zero, score         # 分數歸零
    sw $zero, totalScore    # 總分歸零
    
    # 初始化 Stack
    sw $zero, stackPtr      # 指標歸零
    li $t0, -1
    sw $t0, lastIdx         # 上次樓梯設為 -1 (代表還沒踩過)



# 遊戲主迴圈
GameLoop:
    #計時器更新
    lw $t0, frameCounter    # 讀取目前幀數
    addi $t0, $t0, 1    
    sw $t0, frameCounter    # 存回去
    
    #自動加分機制
    lw $t1, score           # 讀取能量條分數
    addi $t1, $t1, 1
    sw $t1, score
    lw $t2, totalScore      # 讀取總分
    addi $t2, $t2, 1
    sw $t2, totalScore

    #檢查是否升級
    jal CheckLevelUp        # 跳去檢查函式

    #畫面清除
    # 原理：先把舊的東西都畫成黑色 all to black 
    lw $a1, playerX         # 準備玩家 X
    lw $a2, playerY         # 準備玩家 Y
    lw $a3, colorBG         # 顏色：黑色
    jal DrawPlayerPixel     # 呼叫畫畫函式要把玩家塗黑

    lw $a0, colorBG
    lw $a1, colorBG
    jal DrawPlatforms       # 把所有樓梯塗黑

    jal EraseScoreBar       # 把下面藍條塗黑
    jal UpdateHPBar         # 更新(重畫)血條

    #鍵盤輸入偵測 MMIO


    li $t0, 0xffff0000
    lw $t1, 0($t0)          # 讀取狀態
    beq $t1, 0, Physics     # 如果是 0 (沒按鍵)，直接跳去物理運算
    
    # 有按鍵 !
    lw $t2, 0xffff0004
    beq $t2, 111, PauseGame   # 如果是   'o' (111)  ,暫停
    beq $t2, 97, move_left    # 如果是 ' a' (97), 向左
    beq $t2, 100, move_right  # 如果是 'd' (100)  ,向右
    j Physics                 # 其他按鍵忽略去物理

#暫停遊戲 ! 
PauseGame:
	#要重新畫全部 ! 
    lw $a0, colorPlat       # 樓梯
    lw $a1, colorItem       # 加分 星星
    jal DrawPlatforms       # 去畫樓梯
    jal DrawScoreBar        # 去畫藍條
    lw $a1, playerX
    lw $a2, playerY
    lw $a3, colorPlayer     # 抓玩家顏色
    jal DrawPlayerPixel     # 去畫玩家
    
    li $v0, 4
    la $a0, str_paused
    syscall                 # 後台印出 PAUSED 

#一直重複暫停迴圈 直到 按下 p 繼續 遊戲
PauseLoop:
    
    li $t0, 0xffff0000
    lw $t1, 0($t0)
    beq $t1, 0, PauseLoop     # 沒按鍵  繼續等
    lw $t2, 0xffff0004
    beq $t2, 112, ResumeGame  # 按下 'p'了解除暫停
    j PauseLoop


#可以繼續遊戲了
ResumeGame:
    li $v0, 4
    la $a0, str_resumed
    syscall
    j Physics                 # 回到物理運算

#左右移動邏輯
move_left:
    lw $t0, playerX
    subi $t0, $t0, 1        # X 減 1 ,向左移
    blt $t0, 0, Physics     # 如果 X < 0 出界 不能移動
    sw $t0, playerX         # 存回新位置
    j Physics

move_right:
    lw $t0, playerX
    addi $t0, $t0, 1        # X 加 1 ,向右移
    bgt $t0, 63, Physics    # 如果 X > 63 出界 不能移動
    sw $t0, playerX
    j Physics





# 物理運算：樓梯的移動、玩家 重力掉落、撞天花板、吸附樓梯上 
Physics:
    # 樓梯移動 (每 5 幀動一次)
    lw $t0, frameCounter
    rem $t1, $t0, 5         # frameCounter % 5 去運算
    bnez $t1, CheckGravity 
    jal UpdatePlatforms     # 餘數為 0 樓梯更新


#檢查是否踩到樓梯
CheckGravity:
    
    jal CheckStandOnPlatform
    # CheckStandOnPlatform 會回傳 $v0 1=踩到 0=沒踩到
    beq $v0, 1, SnapToPlatform # 踩到了！跳去吸附邏輯
    
    #沒踩到 -> 重力下墜
    lw $t0, frameCounter
    andi $t0, $t0, 1        
    bnez $t0, CheckBounds   
    
    lw $s1, playerY
    addi $s1, $s1, 1        # Y 加 1 往下掉
    sw $s1, playerY
    j CheckBounds
	
	
#吸附在樓梯上
SnapToPlatform:

    # 當樓梯往上移 玩家也要跟著往上
    subi $s1, $v1, 1        # 玩家Y = 樓梯Y - 1
    sw $s1, playerY

    #Stack 紀錄路徑
    lw $t8, lastIdx         # 讀取樓梯編號
    beq $t8, $a0, CheckItemLogic
    

    sw $a0, lastIdx
    
    lw $t9, stackPtr 
    li $t7, 400 
    bge $t9, $t7, CheckItemLogic
    
    la $t6, platStack       # Stack 起始位址
    add $t6, $t6, $t9       # 計算目前位址
    sw $a0, 0($t6)          # 把樓梯編號丟進去
    
    addi $t9, $t9, 4      
    sw $t9, stackPtr      



#檢查有沒有加分星星可以吃
CheckItemLogic:

    la $t1, platItem        # 讀取星星陣列
    sll $t0, $a0, 2       
    add $t1, $t1, $t0
    lw $t2, 0($t1)          # 讀取該樓梯有沒有星星
    beq $t2, 1, EatItem     # 有 (1)  吃掉
    j CheckBounds
	
	
#吃星星
EatItem:
    sw $zero, 0($t1)        # 把星星變不見 (設為0)
    
    # 分數 + 500
    lw $t3, score
    addi $t3, $t3, 500 
    sw $t3, score
    
    lw $t4, totalScore
    addi $t4, $t4, 500
    sw $t4, totalScore
    
    li $v0, 4
    la $a0, str_item
    syscall
    jal PrintStatus         # 分數文字 更新
    j CheckBounds


#撞到天花板?
CheckBounds:
    lw $s1, playerY
    ble $s1, 1, HitCeiling    # 如果 Y <= 1 撞到天花板
    bge $s1, 31, FallRespawn  # 如果 Y >= 31 掉到虛空
    j DrawAll                 # 都沒事  去畫畫


#掉到虛空的動作
FallRespawn:


    lw $t0, hp #扣 1/4 血
    subi $t0, $t0, 4
    sw $t0, hp
    blez $t0, GameOver        # 如果血量 歸零 遊戲結束
    
    #Stack 回朔動作 回朔到上一個樓梯
    lw $t9, stackPtr
    blez $t9, DefaultRespawn  # 如果 Stack 是空的(沒有樓梯)  就去預設重生點
    

    subi $t6, $t9, 4
    la $t7, platStack
    add $t7, $t7, $t6
    lw $t5, 0($t7)         
    
    #傳送玩家回去 讀出來的樓梯位置
    la $t1, platX
    sll $t4, $t5, 2
    add $t1, $t1, $t4
    lw $s0, 0($t1)
    sw $s0, playerX           # 設定玩家 X 座標
    
    la $t2, platY
    add $t2, $t2, $t4
    lw $s1, 0($t2)
    subi $s1, $s1, 1
    sw $s1, playerY           # 設定玩家 Y 座標
    
    sw $t5, lastIdx           # 記得更新 lastIdx
    
    li $v0, 4
    la $a0, str_respawn       # 後台印出重生訊息
    syscall
    jal PrintStatus
    j DrawAll




# 備案：如果 Stack 是空的，就隨便把人放在上面
DefaultRespawn:
    
    li $s1, 2
    sw $s1, playerY
    li $t8, -1
	
	
    sw $t8, lastIdx
    li $v0, 4
    la $a0, str_respawn
    syscall
	
    jal PrintStatus
    j DrawAll #全畫


#撞到天花板
HitCeiling:

    lw $t0, hp
    subi $t0, $t0, 4
    sw $t0, hp

    addi $s1, $s1, 2
    sw $s1, playerY
    blez $t0, GameOver 
    jal PrintStatus
    j DrawAll


# 繪圖區 (Rendering)

DrawAll:
    #畫樓梯與加分星星
    lw $a0, colorPlat       
    lw $a1, colorItem       
    jal DrawPlatforms       # 呼叫畫樓梯函式
    
    #  畫下方藍色加分條
    jal DrawScoreBar
	
	
    #畫上方紅色血條
    jal UpdateHPBar

    #畫玩家
    lw $a3, colorPlayer
    j CallDrawPlayer


CallDrawPlayer:
    lw $a1, playerX
    lw $a2, playerY
    jal DrawPlayerPixel
    
    #速度控制
    li $v0, 32              
    li $a0, 30              
    syscall
    j GameLoop              




#遊戲結數
GameOver:
    li $v0, 4
    la $a0, str_gameover
    syscall
    li $v0, 1
    lw $a0, totalScore      # 印出總分
    syscall
    li $v0, 10              
    syscall


#輔助函式區(下面)


# 確認升級 吃星星 吃四次 回1/4血
CheckLevelUp:
    lw $t0, score
    li $t1, 2000
    blt $t0, $t1, CLU_Done  # 分數 < 2000  離開
    
    # 升級了！
    sw $zero, score         #  藍條歸零
    
    lw $t2, hp
    addi $t2, $t2, 4        #血量 +4
    bgt $t2, 16, CapHP      # 血量超過上限就修正 不加
    j SaveHP
CapHP:
    li $t2, 16              # 血量上限是 16
SaveHP:
    sw $t2, hp
    
    li $v0, 4
    la $a0, str_levelup     
    syscall
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal PrintStatus
    lw $ra, 0($sp)
    addi $sp, $sp, 4
CLU_Done:
    jr $ra




#更新樓梯位置
UpdatePlatforms:
    addi $sp, $sp, -4
	
	
    sw $ra, 0($sp)
    lw $t0, platCount
    la $t1, platX
    la $t2, platY
	
    la $t8, platItem
    li $t3, 0
	
	
#樓梯往上跑	
UP_Loop:
    beq $t3, $t0, UP_Done   
    lw $t5, 0($t2)
    subi $t5, $t5, 1        # Y 減 1 
	
	
    blt $t5, 0, UP_Reset    # 如果 Y < 0  重置(到最底)
    sw $t5, 0($t2)
    j UP_Next
	
	
#樓梯重置	
UP_Reset:
    li $t5, 31              # 重置到底部 Y=31
    sw $t5, 0($t2)
    li $v0, 42
    li $a0, 0
    li $a1, 55
    syscall
    sw $a0, 0($t1)          # 隨機 新的 X 座標
    
    li $v0, 42
    li $a0, 0
    li $a1, 10
    syscall
    blt $a0, 3, Spawn       # 30% 機率產生星星
    sw $zero, 0($t8)        # 沒中  設為 0
    j UP_Next
	
#有沒有 生 星星 ,樓梯	
Spawn:
    li $t9, 1
    sw $t9, 0($t8)          # 中了 , 樓梯屬性設為 1 表有星星


# 處理下一個樓梯
UP_Next:
    
    addi $t1, $t1, 4
    addi $t2, $t2, 4
    addi $t8, $t8, 4
    addi $t3, $t3, 1
    j UP_Loop
UP_Done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra



#畫樓梯 和星星
DrawPlatforms:
    addi $sp, $sp, -28
    sw $ra, 0($sp)
 
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    move $s3, $a0           # $s3 = 平台顏色
    move $s4, $a1           # $s4 = 道具顏色
    lw $s0, platCount
    la $t8, platX
    la $t9, platY
    la $s2, platItem
    li $s1, 0
	
	
DP_Loop:
    beq $s1, $s0, DP_Done
    lw $t4, 0($t8)          # X
    lw $a2, 0($t9)          # Y
    addi $t5, $t4, 8        # 平台長度 8
DL_Loop:
    bge $t4, $t5, CheckStar # 畫完 8 格，去檢查星星
    move $a1, $t4
    move $a3, $s3           # 設定顏色
  
    addi $sp, $sp, -20
    sw $t8, 0($sp)
    sw $t9, 4($sp)
    sw $t4, 8($sp)
	
    sw $t5, 12($sp)
	
	
	
    sw $a2, 16($sp)
    jal DrawPlayerPixel
    lw $t8, 0($sp)
	
       lw $t9, 4($sp)
    lw $t4, 8($sp)
    lw $t5, 12($sp)
	
	
    lw $a2, 16($sp)
    addi $sp, $sp, 20
    
    addi $t4, $t4, 1
    j DL_Loop
	
#畫星星 前 先 檢查	
CheckStar:
    lw $t7, 0($s2)
    beqz $t7, DP_Next       # 沒星星 去 下一個
    lw $a1, 0($t8)
    addi $a1, $a1, 3        # 星星應該畫在樓梯中間
    lw $a2, 0($t9)
    subi $a2, $a2, 1        # 星星在樓梯上方 Y-1
    move $a3, $s4           # 顏色青色
    addi $sp, $sp, -8
    sw $t8, 0($sp)
    sw $t9, 4($sp)
    jal DrawPlayerPixel     # 去畫星星
    lw $t8, 0($sp)
    lw $t9, 4($sp)
    addi $sp, $sp, 8
	
	
DP_Next:
    addi $t8, $t8, 4
    addi $t9, $t9, 4
    addi $s2, $s2, 4
    addi $s1, $s1, 1
    j DP_Loop
	
	
	
DP_Done:
  
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    addi $sp, $sp, 28
    jr $ra

#畫單點像素

DrawPlayerPixel:
    # 邊界檢查 (防止畫到螢幕外面報錯)
    blt $a1, 0, DP_End
    bge $a1, 64, DP_End
    blt $a2, 0, DP_End
    bge $a2, 32, DP_End
    
    lw $t0, displayAddress  # 基底位址
    lw $t1, screenWidth     # 64
    

    mul $t2, $a2, $t1  
    add $t2, $t2, $a1   
    sll $t2, $t2, 2      
    add $t2, $t2, $t0     
    
    sw $a3, 0($t2)          # 把顏色 ($a3) 寫進去
DP_End:
    jr $ra

#畫下方藍條
DrawScoreBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    lw $t2, score
    div $t2, $t2, 50        # 長度 = 分數 / 50
    li $t0, 0
	
	
	
DSB_Loop:
    bge $t0, $t2, DSB_End
    move $a1, $t0
    li $a2, 31              # Y = 31 (最底層)
    lw $a3, colorScore      # 藍色
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t2, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t2, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j DSB_Loop
	
	
DSB_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra


#消除下方藍條
EraseScoreBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $t0, 0
    li $t1, 64
	
	
	
ESB_Loop:
    beq $t0, $t1, ESB_End
    move $a1, $t0
    li $a2, 31
    lw $a3, colorBG         # 黑色
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j ESB_Loop
ESB_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# 畫上方血條

UpdateHPBar:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $t0, 0
    li $t1, 64
	
ClearHP:                    # 先整條塗黑
    beq $t0, $t1, DrawHP
    move $a1, $t0
    li $a2, 0
    lw $a3, colorBG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j ClearHP
	
	
	
#再畫紅線
DrawHP: 
    lw $t2, hp
    sll $t1, $t2, 2         # 長度 = HP * 4
    li $t0, 0
DH_Loop:
    bge $t0, $t1, HP_End
    move $a1, $t0
    li $a2, 0
    lw $a3, colorHP
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal DrawPlayerPixel
    lw $t0, 0($sp)
    lw $t1, 4($sp)
    addi $sp, $sp, 8
    addi $t0, $t0, 1
    j DH_Loop
HP_End:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra




#碰撞檢測
CheckStandOnPlatform:
    addi $sp, $sp, -4
    sw $s3, 0($sp)
    lw $t0, platCount
    la $t1, platX
    la $t2, platY
    li $t3, 0
    lw $s0, playerX
    lw $s1, playerY 
    addi $s1, $s1, 1        # 檢查玩家腳下那一格
CS_Loop:
    beq $t3, $t0, CS_No     # 檢查完所有樓梯 如果 沒踩到
    lw $t5, 0($t2)          # 平台 Y
    sub $t6, $s1, $t5       # 玩家腳Y - 平台Y
    beq $t6, 0, CheckX      # 高度一樣 去 檢查 X
    beq $t6, 1, CheckX      # 陷進去一點點 (吸附容錯) 去 檢查 X
    j CS_Next
CheckX:
    lw $t4, 0($t1)          # 平台 X
    blt $s0, $t4, CS_Next   # 玩家太左邊 還是 沒踩到
    addi $t7, $t4, 7        # 平台長度 7 
    bgt $s0, $t7, CS_Next   # 玩家太右邊 還是 沒踩到
    
    # 踩到了！
    li $v0, 1               # 回傳 1
    move $v1, $t5           # 回傳平台 Y
    move $a0, $t3           # 回傳平台 ID
    lw $s3, 0($sp)
    addi $sp, $sp, 4
    jr $ra
	
	
	
CS_Next:
    addi $t1, $t1, 4
    addi $t2, $t2, 4
    addi $t3, $t3, 1
    j CS_Loop
	
	
	
	
CS_No:
    li $v0, 0               # 回傳 0
    lw $s3, 0($sp)
    addi $sp, $sp, 4
    jr $ra

#後台印出狀態文字
PrintStatus:
    li $v0, 4
    la $a0, str_hp
    syscall
    li $v0, 1
    lw $a0, hp
    syscall
    li $v0, 4
    la $a0, str_score
    syscall
    li $v0, 1
    lw $a0, totalScore
    syscall
    li $v0, 4
    la $a0, str_newline
    syscall
    jr $ra