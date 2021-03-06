/*
 CobaltLCD - Used to drive a Cobalt Networks LCD Front Panel
 
 This code is based on example code from the 
 following link, which is in the public domain.
 
 http://www.arduino.cc/en/Tutorial/SerialEvent
 
 */
 
#define LCD_EN  16
#define BUTTON_EN 18
#define BUTTON_TR 19
#define LCD_RS  28
#define LCD_RW  29
#define FAN_PWM  15
#define COMMAND_CHAR ~

#define SCB_AIRCR ((volatile uint32*) (0xE000ED00 + 0x0C))
#define SCB_AIRCR_SYSRESETREQ (1 << 2)
#define SCB_AIRCR_RESET ((0x05FA0000) | SCB_AIRCR_SYSRESETREQ)



// serial input mode defines
#define SERIAL_INPUT_DATA 0
#define SERIAL_INPUT_CMND 1

// default mode is to input to the LCD.
int serInpMode = SERIAL_INPUT_DATA;

// character reference for serial input
unsigned int serOffRef = 0;

// buffer for incoming serial data
char serBuff[32]; 

// include the LCD library code:
#include <LiquidCrystal.h>
#include <string.h>
#include <stdio.h>
//#include <stdlib.h>
#include <ctype.h>
//#include <avr/pgmspace.h>

// character map for the raspberry icon, stored in PROGMEMM
//PROGMEM 
const byte lcd_char_map[6][8] = {
  { B00011, B01100, B10000, B01100, B00011, B01100, B11110, B10001, },
  { B00000, B11011, B00100, B01110, B11111, B01110, B10001, B00000, },
  { B11000, B00110, B00001, B00110, B11000, B00110, B01111, B10001, },
  { B10000, B01011, B01100, B00100, B00101, B00011, B00000, B00000, },
  { B10001, B01110, B10001, B10001, B00000, B10001, B01110, B00000, },  
  { B00001, B11010, B00110, B00100, B10100, B11000, B00000, B00000, }
  
};

// instantiate the LCD Library with our predefined pins
LiquidCrystal CobaltLCD(LCD_RS, LCD_RW, LCD_EN, 20, 21, 22, 0, 1, 25, 26, 27);

// connection tracking
boolean piConnected = false;  // whether the string is complete

char portBuffers[3];



uint32 atouint(char* t) {
    uint32 val = 0;
    while (*t != '\O' && isdigit(*t)) {
        val = val*10 + (*t - '0');
        ++t;
    }
    return val;
}

void setup() {
  // set up the button controller outputs
  pinMode(BUTTON_EN, OUTPUT);
  pinMode(BUTTON_TR, OUTPUT);  
  pinMode(FAN_PWM,  PWM);
  digitalWrite(BUTTON_EN, HIGH);
  digitalWrite(BUTTON_TR, HIGH);
  
  // start the LCD
  CobaltLCD.begin(16,2);
  CobaltLCD.clear();
  
  // wait 3 seconds, this can probably be removed.
  delay(3000);
  
  // print the default booting screen
  CobaltLCD.home();
  CobaltLCD.print("PiCobalt");
  CobaltLCD.setCursor(0,1);
  CobaltLCD.print("Booting...");
 
  // set up the custom RPi logo.
  int curr_char=0;
  int curr_byte=0;
  byte charData[8];

  for(curr_char=0; curr_char < 6; curr_char++){
    for(curr_byte=0; curr_byte < 8; curr_byte++){
     charData[curr_byte] = lcd_char_map[curr_char][curr_byte];
    }
    CobaltLCD.createChar(curr_char, charData);
  }

  // print the top 3 parts of the icon.    
  CobaltLCD.setCursor(13,0);
  CobaltLCD.write(byte(0));
  CobaltLCD.write(byte(1));
  CobaltLCD.write(byte(2));
  
  // print the bottom 3 parts of the icon.
  CobaltLCD.setCursor(13,1);
  CobaltLCD.write(byte(3));
  CobaltLCD.write(byte(4));
  CobaltLCD.write(byte(5));
  
  // initialize serial:
  Serial2.begin(115200);
  Serial2.println("~RPiCobalt v1.0 Starting");
}

void loop() {
  if(Serial2.available() > 0 ) {
    serialEvent();
  }
  // only read the buttons if we are conncted. 
  if(piConnected) {
    readButtons();
  } 
  

}
byte button_map[8]={1, 1, 1, 1, 1, 1, 1, 0 };
byte button_map_prev[8]={1, 1, 1, 1, 1, 1, 1, 0 };
void readButtons(){
  // Disable the LCD
  
  //digitalWrite(LCD_EN, HIGH);
  
  // change pin mode
  int i = 0;
  for(i=20; i<28; i++){
    if(i==23 || i == 24) {
      if(i==23)
        pinMode(0, INPUT);
      else
        pinMode(1, INPUT);   
    } else {
        pinMode(i, INPUT);
    }
  }
  
  int btnChanged=0;
  digitalWrite(BUTTON_EN, LOW);
  digitalWrite(BUTTON_TR, LOW);
  for(i=0; i<7; i++){
    if(i==2 || i == 3) {
      if(i==2)
        button_map[i] = digitalRead(0);
      else
        button_map[i] = digitalRead(1);
    } else
      button_map[i]=digitalRead(i+21);
    if(button_map[i]!=button_map_prev[i]){
      btnChanged=1;
    }
  }
  button_map[7]='\0';
 
  if(btnChanged) { 
    for(i=0; i<7; i++){
    button_map_prev[i]=button_map[i];
      Serial2.print(button_map[i]);
    }
    Serial2.print("\r\n");
    button_map[7]='\0';
  }
  digitalWrite(BUTTON_EN, HIGH);
  digitalWrite(BUTTON_TR, HIGH);
  
  for(i=20; i<28; i++){
    if(i==23 || i == 24) {
      if(i==23)
        pinMode(0, OUTPUT);
      else
        pinMode(1, OUTPUT);   
    } else {
        pinMode(i, OUTPUT);
    }
  }
   
  
}


void checkSerCmd(){

  // this function is where we will be checking serBuff
  // against our list of commands and running the neccessary 
  // code for each

  // NOTE: serBuff is no larger than 32, so no strncmp should be larger
  // than that if you are adding commands here.  Also, it's best if
  // commands dont overlap, because the first one listed would 
  // be executed as well as the second. (ie: ~DIS and ~DISPLAY)

  if(!strncmp(serBuff, "~HLO", 4)) {
    if(piConnected) {
      Serial2.println("~WARN: 301 Already Connected.");
      return;
    }
    // connect request.
    piConnected = true;
    Serial2.println("~Connected");
    
    // clear the bottom line
    CobaltLCD.setCursor(0,1);
    CobaltLCD.print("RPi Connected");
    return;
  }
  
  if(!strncmp(serBuff, "~STAT", 5)) {
    // print the status back to the client.
    if(piConnected == false ) {
      Serial2.println("~CNCT");
    } else {
      Serial2.println("~OK");
    }
    return;
  }
  if(!strncmp(serBuff, "~CUR", 4)) {
    CobaltLCD.cursor();
    return;
  }
  if(!strncmp(serBuff, "~NOCUR", 6)){
    CobaltLCD.noCursor();    
    return;
  }
  
  if(!strncmp(serBuff, "~SETCUR", 7)){
    // set the cursor to a particular X,Y posisition.
    //get the X,Y position 
    int i=0;
    // start after the ~cur in the string.
    for(i=5; i< strlen(serBuff); i++){
      if(serBuff[i] == ',')
        break;      
    }
    
    if(i==strlen(serBuff)){
       // we didn't find a comma, so the user did not specify the position right.
       Serial2.println("~ERROR:  405 Cursor location error.  Cursor location not set.");
       return;
    }
  
    // if we found a comma, let's get the two values.
    char tmpVal[32];
    int xval=0, yval=0;
    serBuff[i]='\0'; // set the comma to a null char.
    xval = atouint(&serBuff[5]);
    yval = atouint(&serBuff[i+1]);
    if(yval == 0 || yval == 1){
      // looks good for x, check y
      if(xval>=0 && xval<17){
       /*Serial2.print("~Cursor set: ");
       Serial2.print(xval);
       Serial2.print(", ");
       Serial2.println(yval);*/
       CobaltLCD.setCursor(xval,yval);
      }
    }
    return;
  }
  
  if(!strncmp(serBuff, "~DIS", 4)) {
    // client requested disconnect.
    piConnected = false;
    CobaltLCD.home();
    CobaltLCD.clear();
    CobaltLCD.home();
    CobaltLCD.print("PiCobalt");
    CobaltLCD.setCursor(0,1);
    CobaltLCD.print("Disconnected");
    
    // print the top 3 parts of the icon.    
    CobaltLCD.setCursor(13,0);
    CobaltLCD.write(byte(0));
    CobaltLCD.write(byte(1));
    CobaltLCD.write(byte(2));
    
    // print the bottom 3 parts of the icon.
    CobaltLCD.setCursor(13,1);
    CobaltLCD.write(byte(3));
    CobaltLCD.write(byte(4));
    CobaltLCD.write(byte(5));
    
    delay(5);
    *(SCB_AIRCR) = SCB_AIRCR_RESET;
    return;
  }
  
  if(!strncmp(serBuff, "~SETFAN", 7)){
    int fanval = 0;
    Serial2.println(&serBuff[8]);
    fanval = atouint(&serBuff[8]);
    Serial2.print("~Setting FAN to ");
    Serial2.println(fanval);
    pwmWrite(FAN_PWM, fanval * 655);
    return;
  }
  Serial2.println("~ERROR: 402 Unrecognized Command.");
  
}

unsigned char serialRead() {
  if(Serial2.available() > 0) {
    return Serial2.read(); 
  } else {
    return 0;
  }
}
 /*
  SerialEvent occurs whenever a new data comes in the
 hardware serial RX.  This routine is run between each
 time loop() runs, so using delay inside loop can delay
 response.  Multiple bytes of data may be available.
 */
void serialEvent() {
  // TODO: This function needs some serioius cleanup and/or
  // possible reworking.
  
  // Function Rework Notes: 
  // XXX: We cannot rely on Serial2.available to give us bytes available.
  // XXX: We also cannot rely on the user for perfectly timed input.
  // XXX: We must account for delays between bytes.
  // XXX: Perhaps using a serial input mode structure like
  //       - COMMAND_MODE
  //       - DATA_MODE
  // when in either of these modes, you cannot switch until the serOffRef is reset
  // to 0 (zero) with a newline character or in the case of the LCD Data, after a 
  // loop around after 32 characters.
  //
  // Default mode should be LCD Data Input.
  // data should be read from the serial port until a NULL character or a negative 
  // character is read, indicating no more data.(Since we cannot rely on Serial2.available.)
  
  char tmpChar = 0;
  
  // we can assume at least one byte because this function is called when new data is 
  // available on the serial line.
  tmpChar = serialRead();
  
  // this will exit when no new characters are read.
  while(tmpChar > 0 && tmpChar < 128) {
    //Serial2.println(serOffRef);
    if(tmpChar == '\n'  || tmpChar == '\r' || serOffRef > 31) { 
      // if we get a newline, or we are larger than 32 characters, 
      // so time to reset serOffRef and if in 
      // command mode, reset to data mode.
      
      // new line at the beginning, or empty line, is a status request
      if((tmpChar == '\n' || tmpChar == '\r') && serOffRef == 0) {
        // print the status back to the client.
        if(piConnected == false ) {
          Serial2.println("~CNCT");
        } else {
          Serial2.println("~OK");
        }        
      }
      
      // reset serOffRef
      serOffRef = 0;
      if(serInpMode == SERIAL_INPUT_CMND) {
        // Check the command, callout?
        checkSerCmd();
        // clear the serBuff
        int i=0;
        for(i=0; i<32; i++)
          serBuff[i]='\0';
        serInpMode = SERIAL_INPUT_DATA;
        // all following characters will be LCD Characters.
      }

      // skip this character and get the next one.
      tmpChar = serialRead();
      continue; 
    }
    
    if(tmpChar == '~' && serOffRef == 0){
      // if we get a ~ at the beginning of a "line", this means what follows until
      // the next newline is a command, so switch to command mode.
      serInpMode = SERIAL_INPUT_CMND;
    }
    
    if((serOffRef == 0 && serInpMode == SERIAL_INPUT_DATA && piConnected)) {
      // first character of a new display in data mode, not a new line, 
      // clear the LCD
      CobaltLCD.home();
      CobaltLCD.clear();
      CobaltLCD.home();
    }
    
    // a read could have happened above, so let's double check we have a character
    if(tmpChar <= 0 || tmpChar > 127) {
      // nope, leave the loop and exit the function
      break;
    }
    
    // ok we have a character, so let's process it.
    switch (serInpMode) {
      case SERIAL_INPUT_DATA:
        // we are in data mode, so let's just spit the character out to the LCD
        // but only if the pi is connected.
        if(piConnected){
          if(serOffRef == 16) {
            // move to line two if we are greater than 16 chars
            CobaltLCD.setCursor(0,1);
          }
          CobaltLCD.print(tmpChar);
        }
        break;
      case SERIAL_INPUT_CMND: 
        // we are in command mode, so add the character to the buffer.
        serBuff[serOffRef] = tmpChar;
        break;
      default:
        // in an unknown state, print that back to the pi
        Serial2.println("~ERROR: 401 Unknown Serial State, send enter to reset.");  
    }
  
    // everything is done, so let's read the next char and increment the offset
    // buffer.
    tmpChar = serialRead();
    serOffRef++;  
  }
  
}

