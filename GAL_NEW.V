`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//单级GAL运算修改版：
//一切输入输出都为有符号数，一切运算皆调用IP核
//输入为有符号复数，实部在高位，虚部在低位。输入数据归一化之后进行Q15编码
//当某一级的fn,bn开始更新时，信号refresh_begin有效，下一级开始接收上一级输出并计算kappa
//////////////////////////////////////////////////////////////////////////////////
module my_gal( 
clk,ce,reset,  fn_in, fn_out, kappa, bn_in, bn_out ,refresh_begin 
                                   //该算法只完成单级GAL
    );
input  clk; 
input reset;
input ce;   //使能，当上一级的fn,bn开始更新的时候，本级开始使能，所以ce连接到上一级的refresh_begin
input [31:0] fn_in;
input [31:0] bn_in;

output [31:0] fn_out;
output [31:0] bn_out;
output [31:0] kappa;
output refresh_begin;

reg [31:0] fn_out;              //将输出全部寄存
reg [31:0] bn_out;

wire [31:0] fn_out_wire;               
wire [31:0] bn_out_wire;

reg [15:0] kappa_real_reg;  //寄存kappa
reg [15:0] kappa_img_reg;

wire [15:0] kappa_real;  //寄存kappa
wire [15:0] kappa_img;


wire [31:0] kappa_real_int;  //kappa整数             
wire [31:0] kappa_img_int;  

wire [7:0] kappa_img_frac;   //kappa小数，8位，精度0.00003
wire [7:0] kappa_real_frac;                       

wire [15:0] kappa_bn_real;       //寄存kappa_conj*bm-1(n-1)的实部和虚部
wire [15:0] kappa_bn_img; 
wire [15:0] kappa_fn_real;       //寄存kappa*fm-1(n)的实部和虚部
wire [15:0] kappa_fn_img;  

wire [25:0] fn_bn_real;          //寄存bm-1(n-1)*fm-1(n)的实部和虚部
wire [25:0] fn_bn_img;      

wire [31:0] sigema_real;              //累加和的寄存,kappa的分子
wire [31:0] sigema_img;
wire [31:0] sigema_real_wire;
wire [31:0] sigema_img_wire;

wire [16:0] fn_squar;            //fn的模平方
wire [15:0] fn_img_squar;
wire [15:0] fn_real_squar;

wire [16:0] bn_squar;             //bn的模平方
wire [15:0] bn_img_squar;
wire [15:0] bn_real_squar;

wire [25:0] squar_add;           //平方和的寄存，kappa的分母
wire [25:0] squar_add_wire;       //用于反馈
wire [17:0] fn_bn_squar;

reg [31:0] fn_cache[0:5];   //缓存fn，bn为了满足更新的时序
reg [31:0] bn_cache[0:6]; 
reg [31:0] clean;

reg refresh_begin;    //fn,bn完成更新，并且开始输出
wire refresh_begin_wire;

parameter  N =595;              //输入的点数
parameter kappa_out_time =649;    //从reset开始到kappa算完需要的时间，通过仿真得到
parameter refresh_delay =2;      //延迟2个clk，进入更新流程

reg [9:0]  cnt;        //计数器，使能更新

assign refresh_begin_wire =refresh_begin;

assign squar_add =squar_add_wire & clean;       //反馈
assign sigema_real =sigema_real_wire & clean;   //反馈
assign sigema_img =sigema_img_wire & clean ;     //反馈
assign kappa={kappa_real_reg,kappa_img_reg};

always@(posedge clk )    begin 
    bn_cache[0] <=bn_in;             //完成对bn输入延时7clk
    bn_cache[1] <=bn_cache[0];
    bn_cache[2] <=bn_cache[1];
    bn_cache[3] <=bn_cache[2];
    bn_cache[4] <=bn_cache[3];
    bn_cache[5] <=bn_cache[4];   
    bn_cache[6] <=bn_cache[5];      
    
    fn_cache[0] <=fn_in;             //完成对fn输入延时6clk
    fn_cache[1] <=fn_cache[0];
    fn_cache[2] <=fn_cache[1];
    fn_cache[3] <=fn_cache[2];
    fn_cache[4] <=fn_cache[3];
    fn_cache[5] <=fn_cache[4];    
end

always @(posedge clk) begin    //反馈清0
    if(ce)
    clean <=32'b1111_1111_1111_1111_1111_1111_1111_1111;
    else
    clean <=32'b0;
end
                         
always@(posedge clk )    begin         //完成fn和bn的更新
    if(cnt >=kappa_out_time + refresh_delay )  begin //fn,bn开始更新
    fn_out<=fn_out_wire;
    bn_out<=bn_out_wire;   
    end 
    else begin 
    fn_out <=0;
    bn_out<=0;
    end    
end

always@(posedge clk )    begin     //refresh_begin 信号模块，该信号表明fn,bn可以进入更新     
    if(cnt >=kappa_out_time + refresh_delay && ce==1)
    refresh_begin <=1;    
    else
    refresh_begin <=0;
end


always @ (posedge clk) begin    //kappa模块
    if(cnt <kappa_out_time ) begin
    kappa_real_reg <=kappa_real;    
    kappa_img_reg <=kappa_img;    
    end
    else begin
    kappa_real_reg <=kappa_real_reg;   //kappa从此保持不变 
    kappa_img_reg <=kappa_img_reg;
    end
end

always @ (posedge clk) begin    //cnt模块
        if(!reset || !ce)
        cnt <=0;
        else  begin
        if    (refresh_begin ==1)    //停止计数，避免溢出（溢出会清0）
        cnt <=cnt;
        else
        cnt <=cnt+1;     
        end
end
            

//---------------------------------------------------------------------------------------------------
//完成对kappa的求解，Q8*Q7=Q15编码
 add168 add168_1(
  .clk(clk), .a({kappa_real_int[8:0],7'b0}), .b(kappa_real_frac), .s(kappa_real)    //16b+8b=16b
);

add168 add168_2(
  .clk(clk), .a({kappa_img_int[8:0],7'b0}), .b(kappa_img_frac), .s(kappa_img)
);
//-----------------------------------------------------------------------------------------------------
//完成求kappa的整数跟小数,结果为Q8编码
//分子为Q24编码，分母为Q15编码，结果为Q9编码    
//实际的kappa还要乘以2，这里没有乘（为了保证除数与被除数的精度）。求得的结果除以2^8即为最终kappa
//等效于求解kappa的Q8编码值
//除法器最大只支持32位除法，延时44clock
 div32 div32_1 (
  .clk(clk), .dividend(-sigema_img), .divisor(squar_add),
  .quotient(kappa_img_int), .fractional(kappa_img_frac)     //虚部相除,32b/26b=32b余8小数
);
        
 div32 div32_2 (
  .clk(clk), .dividend(-sigema_real),  .divisor(squar_add),
  .quotient(kappa_real_int), .fractional(kappa_real_frac)    //实部相除,32b/26b=32b余8小数
);
//-------------------------------------------------------------------------------------------------------------------------------------------
//求kappa的分子sigema

 add32 add32_1(
  .clk(clk), .a(sigema_img), .b(fn_bn_img), .s(sigema_img_wire)   //sigema虚部更新,32b+26b=32b,多次累加要防止溢出，位宽增加为32b,Q24编码
);


 add32 add32_2(
  .clk(clk), .a(sigema_real), .b(fn_bn_real), .s(sigema_real_wire)  //sigema实部更新,32b+26b=32b,多次累加要防止溢出,Q24编码
);
//-------------------------------------------------------------------------------------------------------------
//求kappa的分母

 add26 add26_1 (                                       //fn和bn的模平方和累加,26b+18b=26b,Q15编码
  .clk(clk), .a(squar_add), .b(fn_bn_squar), .s(squar_add_wire)
);    

 add17 add17_1 (                                       //fn和bn的模平方和,17b+17b=18b ,Q15编码
  .clk(clk), .a(fn_squar), .b(bn_squar), .s(fn_bn_squar)
);    
        
 add16 add16_1 (                                       //fn模平方,16b+16b=17b ,防止溢出,Q15编码
  .clk(clk), .a(fn_img_squar), .b(fn_real_squar), .s(fn_squar)
);

 add16 add16_2(                                       //bn模平方,16b+16b=17b ，防止溢出,Q15编码
  .clk(clk), .a(bn_img_squar), .b(bn_real_squar), .s(bn_squar)
);

 mult16 mult16_1 (
  .clk(clk), .a(fn_in[15:0]), .b(fn_in[15:0]), .p(fn_img_squar)  //fn虚部平方,16b*16b=16b,Q15编码,取[30:15]
);

 mult16 mult16_2 (
  .clk(clk), .a(fn_in[31:16]), .b(fn_in[31:16]), .p(fn_real_squar)  //fn实部平方,16b*16b=16b,Q15编码
);

 mult16 mult16_3 (
  .clk(clk), .a(bn_cache[0][15:0]), .b(bn_cache[0][15:0]), .p(bn_img_squar)  //bn虚部平方,16b*16b=16b,Q15编码
);

 mult16 mult16_4 (
  .clk(clk), .a(bn_cache[0][31:16]), .b(bn_cache[0][31:16]), .p(bn_real_squar)  //bn实部平方,16b*16b=16b,Q15编码
);

//--------------------------------------------------------------------------------------------------------------------------------------
//完成fn和bn的更新

 add16_new add16_new1(
  .clk(clk), .a(fn_cache[5][15:0]), .b(kappa_bn_img), .s(fn_out_wire[15:0])   //fn虚部更新,16b+16b=16b,Q15编码
);


 add16_new add16_new2(
  .clk(clk), .a(fn_cache[5][31:16]), .b(kappa_bn_real), .s(fn_out_wire[31:16])  //fn实部更新,16b+16b=16b
);


 add16_new add16_new3(
  .clk(clk), .a(bn_cache[6][15:0]), .b(kappa_fn_img), .s(bn_out_wire[15:0])   //bn虚部更新,16b+16b=16b
);


 add16_new add16_new4(
  .clk(clk), .a(bn_cache[6][31:16]), .b(kappa_fn_real), .s(bn_out_wire[31:16])  //bn实部更新,16b+16b=16b
);

//----------------------------------------------------------------------------------------------------------------
//完成必须的复数乘法
//复数乘法不仅涉及乘法，还涉及加法，所以对于该输出，不能仅取30:15共16位，否则有可能溢出

 complex_mult complex_mult1 (               //完成kappa*bm-1(n-1)，使用MULT，结果取高位[30:15]，共16位，保持Q15编码
  .clk(clk),
  .ai(kappa_img_reg), .bi(bn_cache[0][15:0]),
  .ar(kappa_real_reg), .br(bn_cache[0][31:16]),
  .pi(kappa_bn_img), .pr(kappa_bn_real)
);

 complex_mult complex_mult2 (               //完成kappa*fm-1(n)，使用MULT，结果取高位[30:15]，保持Q15编码
  .clk(clk), 
  .ai(-kappa_img_reg), .bi(fn_in[15:0]),
  .ar(kappa_real_reg), .br(fn_in[31:16]), 
  .pi(kappa_fn_img), .pr(kappa_fn_real)
);
  
 complex_mult_new   complex_mult_new1(       //bm-1(n-1)*fm-1(n)，使用LUT(实际使用Mult)，结果取高位[31:6]，共26位，Q24编码
  .clk(clk), 
  .ai(fn_in[15:0]), .bi(-bn_cache[0][15:0]),
  .ar(fn_in[31:16]), .br(bn_cache[0][31:16]), 
  .pi(fn_bn_img), .pr(fn_bn_real)
);
                               
endmodule


`timescale 1ns / 1ps
//通过对my_gal模块分时复用，实现求出35个kappa
module new_train_module( 
clk,ce,reset,train_in,gal_refresh_begin,
kappa1,kappa2,kappa3,kappa4,kappa5,kappa6,
kappa7,kappa8,kappa9,kappa10,kappa11,kappa12,
kappa13,kappa14,kappa15,kappa16,kappa17,kappa18,
kappa19,kappa20,kappa21,kappa22,kappa23,kappa24,
kappa25,kappa26,kappa27,kappa28,kappa29,kappa30,  
kappa31,kappa32,kappa33,kappa34,kappa35  
    );
input  clk; 
input reset;
input ce;
input [31:0] train_in;
output [31:0] 
kappa1,kappa2,kappa3,kappa4,kappa5,kappa6,
kappa7,kappa8,kappa9,kappa10,kappa11,kappa12,
kappa13,kappa14,kappa15,kappa16,kappa17,kappa18,
kappa19,kappa20,kappa21,kappa22,kappa23,kappa24,
kappa25,kappa26,kappa27,kappa28,kappa29,kappa30,  
kappa31,kappa32,kappa33,kappa34,kappa35 ;
output gal_refresh_begin;
reg  gal_refresh_begin_reg;

parameter frame_width=595;   
parameter train_delay =9; 
reg [31:0] kappa_vector[1:35];   //寄存所有算出来的kappa
reg [31:0] fn_save[1:frame_width];
reg [31:0] bn_save[1:frame_width];

reg [31:0] fn_in;
reg [31:0] bn_in;
wire [31:0] fn_out;
wire [31:0] bn_out;
wire [31:0] kappa;
wire refresh_begin;
reg [5:0] cnt_loop;
reg [9:0] cnt;

reg train_ce;
wire train_ce_wire;
reg refresh_out;    
wire refresh_out_wire;
reg this_step_end;
wire this_step_end_wire;
reg zero_in ;    //输入填0信号
wire zero_in_wire;

assign gal_refresh_begin =gal_refresh_begin_reg;
assign this_step_end_wire =this_step_end;
assign refresh_out_wire =refresh_out;
assign train_ce_wire =train_ce;
assign zero_in_wire =zero_in;

always@(posedge clk)begin       //cnt_loop模块
 if(!reset || !ce) 
    cnt_loop <=1;
    else if(this_step_end_wire ==1)    //故意生成锁存器
    cnt_loop <=cnt_loop+1;     
end    

always @ (posedge clk) begin   //cnt模块
     if(!reset || !ce) 
     cnt <=0;
     else begin
     cnt <=cnt +1;    
     if(cnt >=651)    //这条语句只在求kappa中起作用，因为更新模块不可能达到652，该句表明更新模块开始
     cnt <=0;
    if(this_step_end_wire ==1) 
     cnt <=0;     
     end
end

always @(posedge clk)begin    //train_ce模块
 if(this_step_end_wire ==1 || !ce) 
 train_ce <=0; 
 else 
 train_ce <=1;
end

/*always@(posedge clk) begin   //fn_in,bn_in模块
    if(train_ce ==1 || refresh_begin==1) begin
        if( !zero_in_wire) begin
        fn_in <=fn_save[cnt-1];
        bn_in <=bn_save[cnt-1];    
        end    
        else begin
        fn_in <=0;
        bn_in <=0; 
        end
        end
    else begin
        fn_in <=0;
        bn_in <=0; 
        end
end   */
always@(posedge clk) begin     //输入模块
    if(zero_in_wire==1) begin
    fn_in <=0;
    bn_in <=0; 
    end
    else begin
    fn_in <=fn_save[cnt-1];
    bn_in <=bn_save[cnt-1];        
    end
end



always@(posedge clk) begin   //fn_save,bn_save模块
//    if(ce && reset) begin
        if(cnt_loop==1  && !refresh_begin) begin   //首次循环
        fn_save[cnt] <=train_in;
        bn_save[cnt] <=train_in;
        end
        else if(refresh_out_wire ==1) begin   //cnt>8，更新开始输出
        fn_save[cnt-train_delay-1] <=fn_out;
        bn_save[cnt-train_delay-1] <=bn_out;    
//    end
end
end


always@(posedge clk)begin      //kappa_vector模块
    if(this_step_end_wire ==1) 
    kappa_vector[cnt_loop] <=kappa;
end


always@(posedge clk) begin    //gal_refresh_begin_reg 模块
    if(cnt_loop >35)
    gal_refresh_begin_reg <=1;   
    else
    gal_refresh_begin_reg <=0;
end

/* always @(posedge clk) begin     //几条信号线
    if(refresh_begin ==1) begin
        if(cnt >=train_delay) 
        refresh_out <=1;
        else 
        refresh_out <=0;
        if (cnt ==frame_width+train_delay) 
        this_step_end <=1;
        else 
        this_step_end <=0;
        end
    else begin
    refresh_out <=0;
    this_step_end <=0;
    end
end    */

always @(posedge clk) begin    //refresh_out信号模块
    if(refresh_begin ==1 && cnt >=train_delay)
    refresh_out <=1;
    else
    refresh_out <=0;
end

always @(posedge clk) begin    //this_step_end信号模块
    if(refresh_begin ==1 && cnt ==frame_width+train_delay)
    this_step_end <=1;
    else
    this_step_end <=0;
end


always @(posedge clk) begin   //填0信号
    if(cnt>=596 || cnt==0) 
    zero_in <=1;
    else 
    zero_in <=0;
end

assign kappa1=kappa_vector[1];
assign kappa2=kappa_vector[2];
assign kappa3=kappa_vector[3];
assign kappa4=kappa_vector[4];
assign kappa5=kappa_vector[5];
assign kappa6=kappa_vector[6];
assign kappa7=kappa_vector[7];
assign kappa8=kappa_vector[8];
assign kappa9=kappa_vector[9];
assign kappa10=kappa_vector[10];
assign kappa11=kappa_vector[11];
assign kappa12=kappa_vector[12];
assign kappa13=kappa_vector[13];
assign kappa14=kappa_vector[14];
assign kappa15=kappa_vector[15];
assign kappa16=kappa_vector[16];
assign kappa17=kappa_vector[17];
assign kappa18=kappa_vector[18];
assign kappa19=kappa_vector[19];
assign kappa20=kappa_vector[20];
assign kappa21=kappa_vector[21];
assign kappa22=kappa_vector[22];
assign kappa23=kappa_vector[23];
assign kappa24=kappa_vector[24];
assign kappa25=kappa_vector[25];
assign kappa26=kappa_vector[26];
assign kappa27=kappa_vector[27];
assign kappa28=kappa_vector[28];
assign kappa29=kappa_vector[29];
assign kappa30=kappa_vector[30];
assign kappa31=kappa_vector[31];
assign kappa32=kappa_vector[32];
assign kappa33=kappa_vector[33];
assign kappa34=kappa_vector[34];
assign kappa35=kappa_vector[35];

my_gal my_gal1( 
.clk(clk),.ce(train_ce_wire), .reset(reset), 
.fn_in(fn_in), .bn_in(bn_in),
.fn_out(fn_out), .bn_out(bn_out),
.kappa(kappa),.refresh_begin(refresh_begin)                                 
    );
endmodule


`timescale 1ns / 1ps
//完成fnbn更新
module fnbn_refresh( clk,reset,
fn_in,bn_in,kappa,
fn_out,bn_out
    );
input clk;
input reset;
input [31:0] fn_in;
input [31:0] bn_in;
input [31:0] kappa;
output [31:0] fn_out;
output [31:0] bn_out;    

reg [31:0] fn_out;
reg [31:0] bn_out; 
wire [31:0] fn_out_wire;
wire [31:0] bn_out_wire;

reg [31:0] fn_cache[0:5];   //缓存fn，bn为了满足更新的时序
reg [31:0] bn_cache[0:6]; 

wire [15:0] kappa_bn_real;       //寄存kappa_conj*bm-1(n-1)的实部和虚部
wire [15:0] kappa_bn_img; 
wire [15:0] kappa_fn_real;       //寄存kappa*fm-1(n)的实部和虚部
wire [15:0] kappa_fn_img;  

     
always@(posedge clk )    begin 
    if(!reset)begin
    fn_out<=0;
    bn_out<=0;    
    end
    else begin
    bn_cache[0] <=bn_in;             //完成对bn输入延时7clk
    bn_cache[1] <=bn_cache[0];
    bn_cache[2] <=bn_cache[1];
    bn_cache[3] <=bn_cache[2];
    bn_cache[4] <=bn_cache[3];
    bn_cache[5] <=bn_cache[4];   
    bn_cache[6] <=bn_cache[5];      
    
    fn_cache[0] <=fn_in;             //完成对fn输入延时6clk
    fn_cache[1] <=fn_cache[0];
    fn_cache[2] <=fn_cache[1];
    fn_cache[3] <=fn_cache[2];
    fn_cache[4] <=fn_cache[3];
    fn_cache[5] <=fn_cache[4];    
    
    fn_out<=fn_out_wire;
    bn_out<=bn_out_wire;
    end
end

//--------------------------------------------------------------------------------------------------------------------------------------
//完成fn和bn的更新

 add16_new add16_new1(
  .clk(clk), .a(fn_cache[5][15:0]), .b(kappa_bn_img), .s(fn_out_wire[15:0])   //fn虚部更新,16b+16b=16b,Q15编码
);


 add16_new add16_new2(
  .clk(clk), .a(fn_cache[5][31:16]), .b(kappa_bn_real), .s(fn_out_wire[31:16])  //fn实部更新,16b+16b=16b
);


 add16_new add16_new3(
  .clk(clk), .a(bn_cache[6][15:0]), .b(kappa_fn_img), .s(bn_out_wire[15:0])   //bn虚部更新,16b+16b=16b
);


 add16_new add16_new4(
  .clk(clk), .a(bn_cache[6][31:16]), .b(kappa_fn_real), .s(bn_out_wire[31:16])  //bn实部更新,16b+16b=16b
);

//---------------------------------------------------------------------------------------------
//完成复数乘法 
 complex_mult complex_mult1 (               //完成kappa*bm-1(n-1)，使用MULT，结果取高位[30:15]，共16位，保持Q15编码
  .clk(clk),
  .ai(kappa[15:0]), .bi(bn_cache[0][15:0]),
  .ar(kappa[31:16]), .br(bn_cache[0][31:16]),
  .pi(kappa_bn_img), .pr(kappa_bn_real)
);

 complex_mult complex_mult2 (               //完成kappa*fm-1(n)，使用MULT，结果取高位[30:15]，保持Q15编码
  .clk(clk), 
  .ai(-kappa[15:0]), .bi(fn_in[15:0]),
  .ar(kappa[31:16]), .br(fn_in[31:16]), 
  .pi(kappa_fn_img), .pr(kappa_fn_real)
);
endmodule


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//35阶GAL
//////////////////////////////////////////////////////////////////////////////////
module gal_cascade35(
 Gal_clk,Gal_reset,Gal_ce,Gal_in,Gal_refresh_begin,
 bn_out1,bn_out2,bn_out3,bn_out4,bn_out5,bn_out6,
 bn_out7,bn_out8,bn_out9,bn_out10,bn_out11,bn_out12,
 bn_out13,bn_out14,bn_out15,bn_out16,bn_out17,bn_out18,
 bn_out19,bn_out20,bn_out21,bn_out22,bn_out23,bn_out24,
 bn_out25,bn_out26,bn_out27,bn_out28,bn_out29,bn_out30,
 bn_out31,bn_out32,bn_out33,bn_out34,bn_out35
    );
input Gal_clk;
input Gal_ce;
input Gal_reset;
input [31:0] Gal_in;   //输入数据
output [31:0]       //系统输出
 bn_out1,bn_out2,bn_out3,bn_out4,bn_out5,bn_out6,
 bn_out7,bn_out8,bn_out9,bn_out10,bn_out11,bn_out12,
 bn_out13,bn_out14,bn_out15,bn_out16,bn_out17,bn_out18,
 bn_out19,bn_out20,bn_out21,bn_out22,bn_out23,bn_out24,
 bn_out25,bn_out26,bn_out27,bn_out28,bn_out29,bn_out30,
 bn_out31,bn_out32,bn_out33,bn_out34,bn_out35;
 
wire [31:0]
 kappa1,kappa2,kappa3,kappa4,kappa5,kappa6,
 kappa7,kappa8,kappa9,kappa10,kappa11,kappa12,
 kappa13,kappa14,kappa15,kappa16,kappa17,kappa18,
 kappa19,kappa20,kappa21,kappa22,kappa23,kappa24,
 kappa25,kappa26,kappa27,kappa28,kappa29,kappa30,  
 kappa31,kappa32,kappa33,kappa34,kappa35;
output  Gal_refresh_begin;
reg [31:0] fn_01;
reg [31:0] bn_01;
wire [31:0] fn_12;  //各模块输入输出的数据线
wire [31:0] bn_12;
wire [31:0] fn_23;  
wire [31:0] bn_23;
wire [31:0] fn_34;  
wire [31:0] bn_34;
wire [31:0] fn_45;  
wire [31:0] bn_45;
wire [31:0] fn_56;  
wire [31:0] bn_56;
wire [31:0] fn_67;  
wire [31:0] bn_67;
wire [31:0] fn_78;  
wire [31:0] bn_78;
wire [31:0] fn_89;  
wire [31:0] bn_89;
wire [31:0] fn_910;  
wire [31:0] bn_910;
wire [31:0] fn_1011;  
wire [31:0] bn_1011;
wire [31:0] fn_1112;  
wire [31:0] bn_1112;
wire [31:0] fn_1213;  
wire [31:0] bn_1213;
wire [31:0] fn_1314;  
wire [31:0] bn_1314;
wire [31:0] fn_1415;  
wire [31:0] bn_1415;
wire [31:0] fn_1516;  
wire [31:0] bn_1516;
wire [31:0] fn_1617;  
wire [31:0] bn_1617;
wire [31:0] fn_1718;  
wire [31:0] bn_1718;
wire [31:0] fn_1819;  
wire [31:0] bn_1819;
wire [31:0] fn_1920;  
wire [31:0] bn_1920;
wire [31:0] fn_2021;  
wire [31:0] bn_2021;
wire [31:0] fn_2122;  
wire [31:0] bn_2122;
wire [31:0] fn_2223;  
wire [31:0] bn_2223;
wire [31:0] fn_2324;  
wire [31:0] bn_2324;
wire [31:0] fn_2425;  
wire [31:0] bn_2425;
wire [31:0] fn_2526;  
wire [31:0] bn_2526;
wire [31:0] fn_2627;  
wire [31:0] bn_2627;
wire [31:0] fn_2728;  
wire [31:0] bn_2728;
wire [31:0] fn_2829;  
wire [31:0] bn_2829;
wire [31:0] fn_2930;  
wire [31:0] bn_2930;
wire [31:0] fn_3031;  
wire [31:0] bn_3031;
wire [31:0] fn_3132;  
wire [31:0] bn_3132;
wire [31:0] fn_3233;
wire [31:0] bn_3233;
wire [31:0] fn_3334;  
wire [31:0] bn_3334;
wire [31:0] fn_3435;  
wire [31:0] bn_3435;
wire [31:0] bn_3536;

assign bn_out1 =bn_12;
assign bn_out2 =bn_23;
assign bn_out3 =bn_34;
assign bn_out4 =bn_45;
assign bn_out5 =bn_56;
assign bn_out6 =bn_67;
assign bn_out7 =bn_78;
assign bn_out8 =bn_89;
assign bn_out9 =bn_910;
assign bn_out10 =bn_1011;
assign bn_out11=bn_1112;
assign bn_out12=bn_1213;
assign bn_out13=bn_1314;
assign bn_out14=bn_1415;
assign bn_out15=bn_1516;
assign bn_out16=bn_1617;
assign bn_out17=bn_1718;
assign bn_out18=bn_1819;
assign bn_out19=bn_1920;
assign bn_out20=bn_2021;
assign bn_out21=bn_2122;
assign bn_out22=bn_2223;
assign bn_out23=bn_2324;
assign bn_out24=bn_2425;
assign bn_out25=bn_2526;
assign bn_out26=bn_2627;
assign bn_out27=bn_2728;
assign bn_out28=bn_2829;
assign bn_out29=bn_2930;
assign bn_out30=bn_3031;
assign bn_out31=bn_3132;
assign bn_out32=bn_3233;
assign bn_out33=bn_3334;
assign bn_out34=bn_3435;
assign bn_out35=bn_3536;

always @(posedge Gal_clk)begin
/*    if(!Gal_ce || !Gal_reset) begin
    fn_01 <=0;
    bn_01 <=0;
   end
    else begin  */
    if(Gal_refresh_begin==1) begin  //更新信号有效时，开始接收输入
    fn_01 <=Gal_in;
    bn_01 <=Gal_in;    
    end
    else  begin
    fn_01 <=0;
    bn_01 <=0;    
    end
//    end
end

fnbn_refresh fnbn_refresh1( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_01),.bn_in(bn_01),.kappa(kappa1),
.fn_out(fn_12),.bn_out(bn_12)
    );
     
fnbn_refresh fnbn_refresh2( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_12),.bn_in(bn_12),.kappa(kappa2),
.fn_out(fn_23),.bn_out(bn_23)
    );
     
fnbn_refresh fnbn_refresh3( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_23),.bn_in(bn_23),.kappa(kappa3),
.fn_out(fn_34),.bn_out(bn_34)
    );
     
fnbn_refresh fnbn_refresh4( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_34),.bn_in(bn_34),.kappa(kappa4),
.fn_out(fn_45),.bn_out(bn_45)
    );
     
fnbn_refresh fnbn_refresh5( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_45),.bn_in(bn_45),.kappa(kappa5),
.fn_out(fn_56),.bn_out(bn_56)
    );
     
fnbn_refresh fnbn_refresh6( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_56),.bn_in(bn_56),.kappa(kappa6),
.fn_out(fn_67),.bn_out(bn_67)
    );
     
fnbn_refresh fnbn_refresh7( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_67),.bn_in(bn_67),.kappa(kappa7),
.fn_out(fn_78),.bn_out(bn_78)
    );
     
fnbn_refresh fnbn_refresh8( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_78),.bn_in(bn_78),.kappa(kappa8),
.fn_out(fn_89),.bn_out(bn_89)
    );
     
fnbn_refresh fnbn_refresh9( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_89),.bn_in(bn_89),.kappa(kappa9),
.fn_out(fn_910),.bn_out(bn_910)
    );
     
fnbn_refresh fnbn_refresh10( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_910),.bn_in(bn_910),.kappa(kappa10),
.fn_out(fn_1011),.bn_out(bn_1011)
    );
     
fnbn_refresh fnbn_refresh11( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1011),.bn_in(bn_1011),.kappa(kappa11),
.fn_out(fn_1112),.bn_out(bn_1112)
    );
     
fnbn_refresh fnbn_refresh12( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1112),.bn_in(bn_1112),.kappa(kappa12),
.fn_out(fn_1213),.bn_out(bn_1213)
    );
     
fnbn_refresh fnbn_refresh13( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1213),.bn_in(bn_1213),.kappa(kappa13),
.fn_out(fn_1314),.bn_out(bn_1314)
    );
     
fnbn_refresh fnbn_refresh14( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1314),.bn_in(bn_1314),.kappa(kappa14),
.fn_out(fn_1415),.bn_out(bn_1415)
    );
     
fnbn_refresh fnbn_refresh15( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1415),.bn_in(bn_1415),.kappa(kappa15),
.fn_out(fn_1516),.bn_out(bn_1516)
    );
     
fnbn_refresh fnbn_refresh16( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1516),.bn_in(bn_1516),.kappa(kappa16),
.fn_out(fn_1617),.bn_out(bn_1617)
    );
     
fnbn_refresh fnbn_refresh17( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1617),.bn_in(bn_1617),.kappa(kappa17),
.fn_out(fn_1718),.bn_out(bn_1718)
    );
     
fnbn_refresh fnbn_refresh18( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1718),.bn_in(bn_1718),.kappa(kappa18),
.fn_out(fn_1819),.bn_out(bn_1819)
    );
     
fnbn_refresh fnbn_refresh19( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1819),.bn_in(bn_1819),.kappa(kappa19),
.fn_out(fn_1920),.bn_out(bn_1920)
    );
     
fnbn_refresh fnbn_refresh20( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_1920),.bn_in(bn_1920),.kappa(kappa20),
.fn_out(fn_2021),.bn_out(bn_2021)
    );

fnbn_refresh fnbn_refresh21( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2021),.bn_in(bn_2021),.kappa(kappa21),
.fn_out(fn_2122),.bn_out(bn_2122)
    );
     
fnbn_refresh fnbn_refresh22( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2122),.bn_in(bn_2122),.kappa(kappa22),
.fn_out(fn_2223),.bn_out(bn_2223)
    );
     
fnbn_refresh fnbn_refresh23( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2223),.bn_in(bn_2223),.kappa(kappa23),
.fn_out(fn_2324),.bn_out(bn_2324)
    );
     
fnbn_refresh fnbn_refresh24( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2324),.bn_in(bn_2324),.kappa(kappa24),
.fn_out(fn_2425),.bn_out(bn_2425)
    );
     
fnbn_refresh fnbn_refresh25( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2425),.bn_in(bn_2425),.kappa(kappa25),
.fn_out(fn_2526),.bn_out(bn_2526)
    );
     
fnbn_refresh fnbn_refresh26( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2526),.bn_in(bn_2526),.kappa(kappa26),
.fn_out(fn_2627),.bn_out(bn_2627)
    );
     
fnbn_refresh fnbn_refresh27( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2627),.bn_in(bn_2627),.kappa(kappa27),
.fn_out(fn_2728),.bn_out(bn_2728)
    );
     
fnbn_refresh fnbn_refresh28( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2728),.bn_in(bn_2728),.kappa(kappa28),
.fn_out(fn_2829),.bn_out(bn_2829)
    );
     
fnbn_refresh fnbn_refresh29( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2829),.bn_in(bn_2829),.kappa(kappa29),
.fn_out(fn_2930),.bn_out(bn_2930)
    );
     
fnbn_refresh fnbn_refresh30( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_2930),.bn_in(bn_2930),.kappa(kappa30),
.fn_out(fn_3031),.bn_out(bn_3031)
    );
     
fnbn_refresh fnbn_refresh31( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_3031),.bn_in(bn_3031),.kappa(kappa31),
.fn_out(fn_3132),.bn_out(bn_3132)
    );
     
fnbn_refresh fnbn_refresh32( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_3132),.bn_in(bn_3132),.kappa(kappa32),
.fn_out(fn_3233),.bn_out(bn_3233)
    );
     
fnbn_refresh fnbn_refresh33( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_3233),.bn_in(bn_3233),.kappa(kappa33),
.fn_out(fn_3334),.bn_out(bn_3334)
    );
     
fnbn_refresh fnbn_refresh34( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_3334),.bn_in(bn_3334),.kappa(kappa34),
.fn_out(fn_3435),.bn_out(bn_3435)
    );
     
fnbn_refresh fnbn_refresh35( 
.clk(Gal_clk),.reset(Gal_reset),
.fn_in(fn_3435),.bn_in(bn_3435),.kappa(kappa35),
.fn_out(),.bn_out(bn_3536)
    );
     
new_train_module new_train_module1( 
.clk(Gal_clk),.ce(Gal_ce),.reset(Gal_reset),.train_in(Gal_in),.gal_refresh_begin(Gal_refresh_begin ),
.kappa1(kappa1),.kappa2(kappa2),.kappa3(kappa3),.kappa4(kappa4),.kappa5(kappa5),.kappa6(kappa6),
.kappa7(kappa7),.kappa8(kappa8),.kappa9(kappa9),.kappa10(kappa10),.kappa11(kappa11),.kappa12(kappa12),
.kappa13(kappa13),.kappa14(kappa14),.kappa15(kappa15),.kappa16(kappa16),.kappa17(kappa17),.kappa18(kappa18),
.kappa19(kappa19),.kappa20(kappa20),.kappa21(kappa21),.kappa22(kappa22),.kappa23(kappa23),.kappa24(kappa24),
.kappa25(kappa25),.kappa26(kappa26),.kappa27(kappa27),.kappa28(kappa28),.kappa29(kappa29),.kappa30(kappa30),  
.kappa31(kappa31),.kappa32(kappa32),.kappa33(kappa33),.kappa34(kappa34),.kappa35(kappa35) 
    );
endmodule