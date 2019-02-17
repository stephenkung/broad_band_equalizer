`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//单级GAL运算修改版：
//一切输入输出都为有符号数，一切运算皆调用IP核
//输入为有符号复数，实部在高位，虚部在低位。输入数据归一化之后进行Q15编码
//当某一级的fn,bn开始更新时，信号refresh_begin有效，下一级开始接收上一级输出并计算kappa
//////////////////////////////////////////////////////////////////////////////////
module my_gal( 
clk,ce, reset,  fn_in, fn_out,  bn_in, bn_out ,refresh_begin 
                                   //该算法只完成单级GAL
    );
input  clk; 
input reset;
input ce;   //使能，当上一级的fn,bn开始更新的时候，本级开始使能，所以ce连接到上一级的refresh_begin
input [31:0] fn_in;
input [31:0] bn_in;

output [31:0] fn_out;
output [31:0] bn_out;
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

reg refresh_begin;    //fn,bn完成更新，并且开始输出
wire refresh_begin_wire;

parameter  N =595;              //输入的点数
parameter kappa_out_time =648;    //从reset开始到kappa算完需要的时间，通过仿真得到
parameter refresh_delay =8;      //从允许更新，到第一点真正开始更新的计算延迟（包含复数乘法、加法以及非阻塞输出）

reg [9:0]  cnt;        //计数器，使能更新

assign refresh_begin_wire =refresh_begin;

assign squar_add =squar_add_wire;       //反馈
assign sigema_real =sigema_real_wire;   //反馈
assign sigema_img =sigema_img_wire;     //反馈

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
                         
always@(posedge clk )    begin         //完成fn和bn的更新
    if((!reset) || (!ce))begin 
    fn_out <=0;
    bn_out<=0;
    cnt <=0;
    kappa_real_reg <=0;
    kappa_img_reg <=0;
    refresh_begin <=0;
    end    
    else begin      
    if(ce) begin     //ce使能的时候，cnt才能开始计数，kappa才能开始计算    
        if (cnt <kappa_out_time )  begin
            cnt <=cnt+1; 
            kappa_real_reg <=kappa_real;    
            kappa_img_reg <=kappa_img;    
            end 
            else begin
           kappa_real_reg <=kappa_real_reg;   //kappa从此保持不变 
            kappa_img_reg <=kappa_img_reg;
            cnt <=cnt+1;  
            end
            if(cnt >=kappa_out_time + refresh_delay )  begin //fn,bn开始有正确更新结果出来的时候（之前的结果都是错误的）
            fn_out<=fn_out_wire;
            bn_out<=bn_out_wire;
            refresh_begin <=1;                 //该信号表明fn,bn开始输出
            cnt <=cnt;                  //停止计数
            end 
        
    /*    if(cnt >=kappa_out_time + refresh_delay )  begin //fn,bn开始有正确更新结果出来的时候（之前的结果都是错误的）
            refresh_begin <=1;                 //该信号表明fn,bn开始输出
            cnt <=cnt;                  //停止计数
            kappa_real_reg <=kappa_real_reg;   //kappa从此保持不变 
            kappa_img_reg <=kappa_img_reg;
            end 
        else    if (cnt >=kappa_out_time )  begin  //kappa刚好求解出来
            refresh_ready <=1;                     //允许fn,bn更新
            cnt <=cnt+1;                   
           kappa_real_reg <=kappa_real_reg;   //kappa从此保持不变 
            kappa_img_reg <=kappa_img_reg;
            end 
        else begin
            cnt <=cnt+1; 
            refresh_ready <=0;
            kappa_real_reg <=kappa_real;    
            kappa_img_reg <=kappa_img;    
            end */
        end 
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
  
 complex_mult_lut   complex_mult_lut1(       //bm-1(n-1)*fm-1(n)，使用LUT(实际使用Mult)，结果取高位[31:6]，共26位，Q24编码
  .clk(clk), 
  .ai(fn_in[15:0]), .bi(-bn_cache[0][15:0]),
  .ar(fn_in[31:16]), .br(bn_cache[0][31:16]), 
  .pi(fn_bn_img), .pr(fn_bn_real)
);
                               
endmodule




`include  "my_gal.v"
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//级联GAL算法
//22阶
//////////////////////////////////////////////////////////////////////////////////
module gal_cascade_22(  
 Gal_clk, Gal_ce, Gal_reset,
 Gal_in, bn_out1,bn_out2,bn_out3,
 bn_out4,bn_out5,bn_out6,
 bn_out7,bn_out8,bn_out9,
 bn_out10,bn_out11,bn_out12,
 bn_out13,bn_out14,bn_out15,
 bn_out16,bn_out17,bn_out18,
 bn_out19,bn_out20,bn_out21,
 bn_out22,
 Gal_refresh_begin 
    );

input Gal_clk;
input Gal_ce;
input Gal_reset;
input [31:0] Gal_in;   //输入数据

output [31:0]       //系统输出
 bn_out1, bn_out2, bn_out3, 
 bn_out4,bn_out5,bn_out6,
 bn_out7,bn_out8,bn_out9,
 bn_out10,bn_out11,bn_out12,
 bn_out13,bn_out14,bn_out15,
 bn_out16,bn_out17,bn_out18,
 bn_out19,bn_out20,bn_out21,
 bn_out22;
output Gal_refresh_begin;

parameter Gal_N =3;    //3级GAL算法

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

wire refresh_begin12;   //各模块信号线
wire refresh_begin23;
wire refresh_begin34;
wire refresh_begin45;
wire refresh_begin56;
wire refresh_begin67;
wire refresh_begin78;
wire refresh_begin89;
wire refresh_begin910;
wire refresh_begin1011;
wire refresh_begin1112;
wire refresh_begin1213;
wire refresh_begin1314;
wire refresh_begin1415;
wire refresh_begin1516;
wire refresh_begin1617;
wire refresh_begin1718;
wire refresh_begin1819;
wire refresh_begin1920;
wire refresh_begin2021;
wire refresh_begin2122;
wire refresh_begin2223;

assign Gal_refresh_begin = refresh_begin2223;
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


my_gal    my_gal1(       
.clk(Gal_clk), .reset(Gal_reset), 
.ce(Gal_ce),.fn_in(Gal_in), .bn_in(Gal_in),
.fn_out(fn_12),  .bn_out(bn_12) ,.refresh_begin (refresh_begin12)
  );

my_gal    my_gal2(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin12), .fn_in(fn_12), .bn_in(bn_12), 
.fn_out(fn_23), .bn_out(bn_23),.refresh_begin (refresh_begin23)

  );
  
my_gal    my_gal3(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin23),.fn_in(fn_23),.bn_in(bn_23),
.fn_out(fn_34), .bn_out(bn_34),.refresh_begin (refresh_begin34)
  );


my_gal    my_gal4(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin34), .fn_in(fn_34), .bn_in(bn_34), 
.fn_out(fn_45), .bn_out(bn_45),.refresh_begin (refresh_begin45)

  );
  
my_gal    my_gal5(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin45),.fn_in(fn_45),.bn_in(bn_45),
.fn_out(fn_56), .bn_out(bn_56),.refresh_begin (refresh_begin56)
  );

my_gal    my_gal6(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin56), .fn_in(fn_56), .bn_in(bn_56), 
.fn_out(fn_67), .bn_out(bn_67),.refresh_begin (refresh_begin67)

  );
  
my_gal    my_gal7(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin67),.fn_in(fn_67),.bn_in(bn_67),
.fn_out(fn_78), .bn_out(bn_78),.refresh_begin (refresh_begin78)
  );

my_gal    my_gal8(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin78), .fn_in(fn_78), .bn_in(bn_78), 
.fn_out(fn_89), .bn_out(bn_89),.refresh_begin (refresh_begin89)

  );
  
my_gal    my_gal9(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin89),.fn_in(fn_89),.bn_in(bn_89),
.fn_out(fn_910), .bn_out(bn_910),.refresh_begin (refresh_begin910)
  );

my_gal    my_gal10(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin910), .fn_in(fn_910), .bn_in(bn_910), 
.fn_out(fn_1011), .bn_out(bn_1011),.refresh_begin (refresh_begin1011)

  );
  
my_gal    my_gal11(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1011),.fn_in(fn_1011),.bn_in(bn_1011),
.fn_out(fn_1112), .bn_out(bn_1112),.refresh_begin (refresh_begin1112)
  );
  
my_gal    my_gal12(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin1112), .fn_in(fn_1112), .bn_in(bn_1112), 
.fn_out(fn_1213), .bn_out(bn_1213),.refresh_begin (refresh_begin1213)

  );
  
my_gal    my_gal13(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1213),.fn_in(fn_1213),.bn_in(bn_1213),
.fn_out(fn_1314), .bn_out(bn_1314),.refresh_begin (refresh_begin1314)
  );

my_gal    my_gal14(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1314),.fn_in(fn_1314),.bn_in(bn_1314),
.fn_out(fn_1415), .bn_out(bn_1415),.refresh_begin (refresh_begin1415)
  );
  
my_gal    my_gal15(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin1415), .fn_in(fn_1415), .bn_in(bn_1415), 
.fn_out(fn_1516), .bn_out(bn_1516),.refresh_begin (refresh_begin1516)

  );
  
my_gal    my_gal16(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1516),.fn_in(fn_1516),.bn_in(bn_1516),
.fn_out(fn_1617), .bn_out(bn_1617),.refresh_begin (refresh_begin1617)
  );
 
my_gal    my_gal17(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1617),.fn_in(fn_1617),.bn_in(bn_1617),
.fn_out(fn_1718), .bn_out(bn_1718),.refresh_begin (refresh_begin1718)
  );

my_gal    my_gal18(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1718),.fn_in(fn_1718),.bn_in(bn_1718),
.fn_out(fn_1819), .bn_out(bn_1819),.refresh_begin (refresh_begin1819)
  );
  
my_gal    my_gal19(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin1819), .fn_in(fn_1819), .bn_in(bn_1819), 
.fn_out(fn_1920), .bn_out(bn_1920),.refresh_begin (refresh_begin1920)

  );
  
my_gal    my_gal20(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin1920),.fn_in(fn_1920),.bn_in(bn_1920),
.fn_out(fn_2021), .bn_out(bn_2021),.refresh_begin (refresh_begin2021)
  ); 
  
my_gal    my_gal21(      
.clk(Gal_clk),.reset(Gal_reset), 
.ce(refresh_begin2021), .fn_in(fn_2021), .bn_in(bn_2021), 
.fn_out(fn_2122), .bn_out(bn_2122),.refresh_begin (refresh_begin2122)

  );
  
my_gal    my_gal22(    
.clk(Gal_clk), .reset(Gal_reset), 
.ce(refresh_begin2122),.fn_in(fn_2122),.bn_in(bn_2122),
.fn_out(fn_2223), .bn_out(bn_2223),.refresh_begin (refresh_begin2223)
  ); 
endmodule