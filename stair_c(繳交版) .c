#include <stdio.h>
#include <stdlib.h>
#include <conio.h>   // 按鍵偵測 (_kbhit, _getch)
#include <windows.h> // 游標控制 (gotoxy) 和 延遲 (Sleep)
#include <time.h>   
#define SCREEN_WIDTH 64
#define SCREEN_HEIGHT 32

// 畫面緩衝區
int displayBuffer[SCREEN_HEIGHT][SCREEN_WIDTH];
int previousBuffer[SCREEN_HEIGHT][SCREEN_WIDTH];

// 符號定義
#define EMPTY 0
#define PLAYER 1
#define PLATFORM 2
#define ITEM 3
#define HP_BAR 4
#define SCORE_BAR 5

// 遊戲變數
int playerX = 32;
int playerY = 10;
int hp = 16;
int score = 0;   
int frameCounter = 0;

// 平台資料
int platCount = 8;
int platX[8] = {10, 50, 30, 5, 45, 20, 55, 15};
int platY[8] = {20, 24, 28, 32, 36, 40, 44, 48};
int platItem[8] = {0, 1, 0, 0, 1, 0, 0, 0}; 

// Stack 堆疊 (掉落時回朔至上一個樓梯)
int platStack[100]; 
int stackPtr = 0;   
int lastIdx = -1;   

//讓玩家在畫面上能順暢移動
void gotoxy(int x, int y) {
    COORD coord;
    coord.X = x;
    coord.Y = y;
    SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), coord);
}
//把終端機的白底線藏起來
void HideCursor() {
    CONSOLE_CURSOR_INFO cursorInfo;
    GetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cursorInfo);
    cursorInfo.bVisible = FALSE; 
    SetConsoleCursorInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cursorInfo);
}

//函式宣告
void GameLoop();
void Physics();
void CheckGravity();
void SnapToPlatform(int platIdx);
void CheckItemLogic(int platIndex);
void EatItem(int platIndex);
void CheckBounds();
void FallRespawn();
void DefaultRespawn();
void HitCeiling();
void DrawAll();
void RenderScreen();
void UpdatePlatforms();
int CheckStandOnPlatform();
void GameOver();
void UpdateHPBar();


int main() {
    system("mode con: cols=80 lines=40");
    HideCursor();
    srand(time(NULL));

    // 初始化緩衝區
    for(int y=0; y<SCREEN_HEIGHT; y++) {
        for(int x=0; x<SCREEN_WIDTH; x++) {
            previousBuffer[y][x] = -1;
            displayBuffer[y][x] = EMPTY;
        }
    }

    printf("Game Start! Press any key...\n");
    _getch();
    system("cls");

    GameLoop();
    return 0;
}

//遊戲邏輯 !! 
void GameLoop() {
    while (1) { //遊戲跑在這
        frameCounter++;
        
        // 清空繪圖區
        for(int y=0; y<SCREEN_HEIGHT; y++) {
            for(int x=0; x<SCREEN_WIDTH; x++) {
                displayBuffer[y][x] = EMPTY;
            }
        }

        // 輸入偵測
        if (_kbhit()) {
            char key = _getch();
            if (key == 'o') { // 暫停
                while(1) { if(_kbhit() && _getch() == 'p') break; } //按 p 繼續
            }
            if (key == 'a') { playerX--; if (playerX < 0) playerX = 0; }
            if (key == 'd') { playerX++; if (playerX > 63) playerX = 63; }
        }

        Physics();
        DrawAll();
    }
}

void Physics() {
    // 調整速度：每 3 幀移動一次樓梯
    if (frameCounter % 3 == 0) {
        UpdatePlatforms();
    }
    CheckGravity();
}

//更新樓梯資訊
void UpdatePlatforms() {
    for (int i = 0; i < platCount; i++) {
        platY[i]--; 
        if (platY[i] < 0) { // 重置樓梯
            platY[i] = 31;
            platX[i] = rand() % 55; 
            
            // 每個樓梯有30% 機率生成星星
            if ((rand() % 10) < 3) platItem[i] = 1;
            else platItem[i] = 0;
        }
    }
}
//判斷重力 玩家沒在樓上 就繼續下降
void CheckGravity() {
    int platIdx = CheckStandOnPlatform();
    
    if (platIdx != -1) {
        SnapToPlatform(platIdx); 
    } else {
        if (frameCounter % 2 == 0) playerY++; // 下墜
        CheckBounds();
    }
}
//每一禎會調用來確認 : 玩家有踩在樓梯上嗎?
int CheckStandOnPlatform() {
    int footY = playerY + 1;
    for (int i = 0; i < platCount; i++) {
        if (footY == platY[i] || footY == platY[i] + 1) {
            if (playerX >= platX[i] && playerX <= platX[i] + 7) {
                return i; 
            }
        }
    }
    return -1;
}

//確認玩家站到平台後 要做什麼
void SnapToPlatform(int platIdx) {
	//玩家位置 設置成 樓梯的 y-1
    playerY = platY[platIdx] - 1;

	//站的樓梯丟到 Stack
    if (lastIdx != platIdx) {
        lastIdx = platIdx;
        if (stackPtr < 100) {
            platStack[stackPtr] = platIdx;
            stackPtr++;
        }
    }
    CheckItemLogic(platIdx);
}

//檢查 樓梯有沒有星星 可以吃
void CheckItemLogic(int platIndex) {
    if (platItem[platIndex] == 1) {
        EatItem(platIndex);
    } else {
        CheckBounds();
    }
}

//吃到星星(加分物) 邏輯
void EatItem(int platIndex) {
    platItem[platIndex] = 0; // 移除星星
    score += 500; //吃到加500分

	//每2000分 也就是 吃 四次星星 就回1/4的血
    if (score > 0 && score % 2000 == 0) { 
        hp += 4;
        if (hp > 16) hp = 16;
        
        // Print 升級提示
        gotoxy(0, SCREEN_HEIGHT + 1);
        printf(">>> LEVEL UP! HP RESTORED! <<<");
    }
    
    CheckBounds();
}

//確認玩家位置 是否 超出 天花板 or 掉入虛空
void CheckBounds() {
    if (playerY <= 1) HitCeiling();
    else if (playerY >= 31) FallRespawn();
}


//掉落扣血 邏輯
void FallRespawn() {
    hp -= 4; // 扣 1/4 血
    if (hp <= 0) GameOver();

	//Stack 
    if (stackPtr <= 0) {
        DefaultRespawn();
        return;
    }
    // Stack Peek (回到上一個樓梯)
    int savedIdx = platStack[stackPtr - 1]; 
    playerX = platX[savedIdx];
    playerY = platY[savedIdx] - 1;
    lastIdx = savedIdx;
    
    gotoxy(0, SCREEN_HEIGHT + 1);
    printf("Oops! Respawn to last step (-4 HP)  .");
}


//預設掉落 的 人物 位置 設定
void DefaultRespawn() {
    playerY = 2;
    lastIdx = -1;
}

//撞到 天花板funtion
void HitCeiling() {
	//撞到 也扣血
    hp -= 4;
    playerY += 2;
    if (hp <= 0) GameOver();
    
    gotoxy(0, SCREEN_HEIGHT + 1);
    printf("OOPS! Hit Ceiling (-4 HP) .");
}

//遊戲結束
void GameOver() {
    system("cls");
    printf("\n\n");
    printf("  ==============================\n");
    printf("===GAME OVER===\n");
    printf("   Score: %d\n", score);
    printf("  ==============================\n");
    printf("\n  Press any key to exit...");
    _getch();
    exit(0);
}

//繪圖區
void DrawAll() {
    // 填入 Buffer
    for (int i = 0; i < platCount; i++) {
        for (int k = 0; k < 8; k++) { // 畫樓梯
            int px = platX[i] + k;
            int py = platY[i];
            if(px >=0 && px < SCREEN_WIDTH && py >=0 && py < SCREEN_HEIGHT)
                displayBuffer[py][px] = PLATFORM;
        }
        if (platItem[i] == 1) { // 畫星星
            int sx = platX[i] + 3;
            int sy = platY[i] - 1;
            if(sx >=0 && sx < SCREEN_WIDTH && sy >=0 && sy < SCREEN_HEIGHT)
                displayBuffer[sy][sx] = ITEM;
        }
    }

  
    UpdateHPBar();  // 畫血條

    // 畫玩家
    if(playerX >=0 && playerX < SCREEN_WIDTH && playerY >=0 && playerY < SCREEN_HEIGHT)
        displayBuffer[playerY][playerX] = PLAYER;

    RenderScreen(); // 印出到螢幕
    
    // 延遲 60ms (讓畫面穩定不閃爍)
    Sleep(60); 
}


//更新血條
void UpdateHPBar() {
    int length = hp * 4;
    for(int i=0; i<length && i<SCREEN_WIDTH; i++) 
        displayBuffer[0][i] = HP_BAR;
}

//畫面更新
void RenderScreen() {
    // 有雙重緩衝，為了防止畫面閃爍	
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            if (displayBuffer[y][x] != previousBuffer[y][x]) {
                gotoxy(x, y);
                int type = displayBuffer[y][x];
                if (type == EMPTY) printf(" ");
                else if (type == PLAYER) printf("O");
                else if (type == PLATFORM) printf("=");
                else if (type == ITEM) printf("*");
                else if (type == HP_BAR) printf("|");
                else if (type == SCORE_BAR) printf("-");
                
                previousBuffer[y][x] = type;
            }
        }
    }
    // 更新下方文字
    gotoxy(0, SCREEN_HEIGHT);

    printf("HP: %02d | Score: %05d", hp, score);
}
