extends RefCounted
## Собранные вручную карты глав героев: путь-коридор с залами и арена владыки в конце.
## Карта неизменна (одни и те же точки при каждом заходе), стены — свои объекты главы.
## Таймер на такой карте — ограничение: дойти до арены и победить владыку, пока не вышло время.

const HeroCh := preload("res://scripts/hero_chapters.gd")

const MAPS := {
	"vega_0": {"pts": [Vector2(0, 0), Vector2(151, -868), Vector2(589, -1426), Vector2(1271, -1686), Vector2(1333, -2565), Vector2(1890, -3252), Vector2(1691, -4045), Vector2(922, -4520), Vector2(551, -5334), Vector2(1006, -6122), Vector2(481, -6867), Vector2(508, -7599), Vector2(-7, -8043), Vector2(-161, -8785)], "w": 300, "rooms": [[3, 340], [5, 397], [8, 474], [10, 340]], "arena": 680},
	"vega_1": {"pts": [Vector2(0, 0), Vector2(903, -321), Vector2(1587, -236), Vector2(1948, -816), Vector2(2782, -811), Vector2(3199, -164), Vector2(2903, 581), Vector2(3344, 1447), Vector2(4098, 1507), Vector2(4807, 2140), Vector2(5696, 2101), Vector2(6268, 1639), Vector2(6447, 841), Vector2(7180, 293), Vector2(7868, 663), Vector2(8590, 108), Vector2(9396, 156), Vector2(10017, 615)], "w": 290, "rooms": [[4, 359], [6, 392], [8, 346], [11, 340], [14, 371]], "arena": 680},
	"vega_2": {"pts": [Vector2(0, 0), Vector2(266, 696), Vector2(-7, 1444), Vector2(338, 2077), Vector2(131, 2868), Vector2(427, 3484), Vector2(268, 4227), Vector2(-459, 4844), Vector2(-514, 5598), Vector2(-1191, 6218), Vector2(-1226, 6958), Vector2(-1671, 7568), Vector2(-1803, 8418), Vector2(-1420, 9008), Vector2(-594, 9165), Vector2(52, 9764), Vector2(331, 10639), Vector2(-168, 11182), Vector2(-184, 11975), Vector2(513, 12579), Vector2(1222, 12293), Vector2(1834, 12620)], "w": 280, "rooms": [[4, 340], [6, 360], [9, 340], [12, 340], [15, 480], [17, 340]], "arena": 680},
	"rin_0": {"pts": [Vector2(0, 0), Vector2(568, -724), Vector2(1425, -669), Vector2(2265, -1050), Vector2(2541, -1736), Vector2(2471, -2497), Vector2(1614, -2858), Vector2(1072, -2390), Vector2(212, -2549), Vector2(14, -3303), Vector2(327, -3923), Vector2(1234, -3974), Vector2(1867, -4452), Vector2(2695, -4350)], "w": 300, "rooms": [[3, 340], [5, 345], [8, 359], [10, 340]], "arena": 680},
	"rin_1": {"pts": [Vector2(0, 0), Vector2(-203, 818), Vector2(177, 1488), Vector2(-204, 2205), Vector2(214, 2878), Vector2(-60, 3573), Vector2(482, 4359), Vector2(568, 5173), Vector2(-53, 5536), Vector2(-72, 6319), Vector2(569, 6690), Vector2(560, 7666), Vector2(918, 8334), Vector2(404, 9055), Vector2(-248, 9373), Vector2(-468, 10031), Vector2(-1181, 10375), Vector2(-1631, 11049)], "w": 290, "rooms": [[4, 340], [6, 407], [8, 340], [11, 347], [14, 340]], "arena": 680},
	"rin_2": {"pts": [Vector2(0, 0), Vector2(-65, -919), Vector2(217, -1619), Vector2(993, -1846), Vector2(1640, -2438), Vector2(1608, -3378), Vector2(1039, -3867), Vector2(1001, -4671), Vector2(553, -5255), Vector2(-189, -5304), Vector2(-448, -5963), Vector2(-91, -6789), Vector2(701, -7055), Vector2(1007, -7917), Vector2(1693, -8142), Vector2(2151, -8680), Vector2(1922, -9579), Vector2(1300, -9994), Vector2(1247, -10871), Vector2(1702, -11407), Vector2(1580, -12135), Vector2(764, -12350)], "w": 280, "rooms": [[4, 476], [6, 350], [9, 340], [12, 434], [15, 340], [17, 347]], "arena": 680},
	"bram_0": {"pts": [Vector2(0, 0), Vector2(-748, -73), Vector2(-1109, -662), Vector2(-1955, -844), Vector2(-2316, -1507), Vector2(-3022, -1590), Vector2(-3648, -1168), Vector2(-3950, -450), Vector2(-4649, -170), Vector2(-5196, 458), Vector2(-5300, 1425), Vector2(-5887, 2105), Vector2(-6809, 1910), Vector2(-7301, 2431), Vector2(-7969, 2240)], "w": 300, "rooms": [[3, 340], [6, 340], [8, 340], [11, 478]], "arena": 680},
	"bram_1": {"pts": [Vector2(0, 0), Vector2(260, 726), Vector2(1013, 934), Vector2(1197, 1677), Vector2(633, 2302), Vector2(783, 3069), Vector2(1558, 3589), Vector2(1992, 4415), Vector2(1825, 5233), Vector2(2304, 5762), Vector2(2511, 6716), Vector2(1940, 7275), Vector2(1074, 7345), Vector2(589, 8155), Vector2(984, 8814), Vector2(1853, 8953), Vector2(2486, 9623)], "w": 290, "rooms": [[3, 355], [6, 520], [8, 340], [10, 389], [13, 358]], "arena": 680},
	"bram_2": {"pts": [Vector2(0, 0), Vector2(6, 925), Vector2(698, 1304), Vector2(885, 1989), Vector2(677, 2891), Vector2(44, 3545), Vector2(151, 4398), Vector2(-247, 5146), Vector2(-988, 5507), Vector2(-1148, 6304), Vector2(-1800, 6559), Vector2(-2244, 7246), Vector2(-2998, 7161), Vector2(-3749, 7499), Vector2(-4284, 8222), Vector2(-4416, 9002), Vector2(-3860, 9513), Vector2(-3917, 10406), Vector2(-4415, 11199), Vector2(-4279, 12002), Vector2(-4488, 12702)], "w": 280, "rooms": [[4, 509], [6, 447], [9, 340], [11, 359], [14, 391], [16, 354]], "arena": 680},
	"kira_0": {"pts": [Vector2(0, 0), Vector2(-720, -143), Vector2(-1114, -785), Vector2(-1870, -1195), Vector2(-2662, -993), Vector2(-3201, -278), Vector2(-3828, -9), Vector2(-4563, -288), Vector2(-5372, -207), Vector2(-5916, -688), Vector2(-6818, -910), Vector2(-7044, -1643), Vector2(-6892, -2556), Vector2(-7407, -3181), Vector2(-8304, -3526)], "w": 300, "rooms": [[3, 397], [6, 340], [8, 340], [11, 346]], "arena": 680},
	"kira_1": {"pts": [Vector2(0, 0), Vector2(-800, -334), Vector2(-1405, -1079), Vector2(-1337, -1985), Vector2(-1963, -2726), Vector2(-1906, -3531), Vector2(-2339, -4184), Vector2(-2352, -4909), Vector2(-3056, -5420), Vector2(-3923, -5300), Vector2(-4153, -4556), Vector2(-4859, -4244), Vector2(-5795, -4434), Vector2(-6070, -5374), Vector2(-6998, -5619), Vector2(-7586, -5024), Vector2(-8267, -5002)], "w": 290, "rooms": [[3, 499], [6, 340], [8, 460], [10, 362], [13, 520]], "arena": 680},
	"kira_2": {"pts": [Vector2(0, 0), Vector2(-318, 605), Vector2(-1220, 574), Vector2(-1671, 1103), Vector2(-2636, 1024), Vector2(-3382, 1377), Vector2(-4208, 1259), Vector2(-4820, 1794), Vector2(-4821, 2578), Vector2(-5452, 3091), Vector2(-5689, 3870), Vector2(-5296, 4672), Vector2(-5556, 5535), Vector2(-4870, 6132), Vector2(-4946, 6981), Vector2(-4199, 7437), Vector2(-3439, 6955), Vector2(-2671, 6888), Vector2(-2246, 7543), Vector2(-2593, 8146), Vector2(-2213, 8825), Vector2(-2251, 9625)], "w": 280, "rooms": [[4, 425], [6, 413], [9, 413], [12, 501], [15, 475], [17, 371]], "arena": 680},
	"skyla_0": {"pts": [Vector2(0, 0), Vector2(-776, 186), Vector2(-1407, -412), Vector2(-2116, -203), Vector2(-2359, 441), Vector2(-1737, 1122), Vector2(-2058, 1911), Vector2(-2916, 2366), Vector2(-3015, 3168), Vector2(-3757, 3728), Vector2(-3671, 4632), Vector2(-3255, 5183), Vector2(-3429, 5925), Vector2(-3993, 6520)], "w": 300, "rooms": [[3, 340], [5, 431], [8, 388], [10, 340]], "arena": 680},
	"skyla_1": {"pts": [Vector2(0, 0), Vector2(330, 810), Vector2(-177, 1463), Vector2(-345, 2416), Vector2(-103, 3058), Vector2(-656, 3683), Vector2(-537, 4589), Vector2(-1100, 5138), Vector2(-1168, 5947), Vector2(-482, 6456), Vector2(408, 6589), Vector2(900, 7199), Vector2(944, 8147), Vector2(1370, 8890), Vector2(2115, 9154), Vector2(2770, 8600), Vector2(2900, 7667)], "w": 290, "rooms": [[3, 340], [6, 376], [8, 401], [10, 372], [13, 380]], "arena": 680},
	"skyla_2": {"pts": [Vector2(0, 0), Vector2(582, -787), Vector2(1334, -845), Vector2(1726, -1558), Vector2(2574, -1788), Vector2(3333, -1348), Vector2(4124, -1608), Vector2(4348, -2467), Vector2(4071, -3095), Vector2(4635, -3784), Vector2(4326, -4539), Vector2(4869, -5283), Vector2(4487, -5954), Vector2(4990, -6767), Vector2(5934, -6660), Vector2(6407, -7324), Vector2(7163, -7681), Vector2(7636, -8307), Vector2(8570, -8521), Vector2(9188, -9029), Vector2(9287, -9727)], "w": 280, "rooms": [[4, 477], [6, 432], [9, 415], [11, 371], [14, 415], [16, 383]], "arena": 680},
	"orm_0": {"pts": [Vector2(0, 0), Vector2(63, -945), Vector2(540, -1603), Vector2(413, -2286), Vector2(-34, -2887), Vector2(-97, -3687), Vector2(540, -4415), Vector2(1184, -4673), Vector2(1245, -5410), Vector2(2116, -5777), Vector2(2553, -6627), Vector2(2546, -7362), Vector2(2069, -8128), Vector2(2571, -8898)], "w": 300, "rooms": [[3, 340], [5, 381], [8, 340], [10, 340]], "arena": 680},
	"orm_1": {"pts": [Vector2(0, 0), Vector2(-549, -794), Vector2(-1382, -945), Vector2(-1850, -352), Vector2(-2645, -434), Vector2(-3438, 21), Vector2(-4161, -47), Vector2(-4950, -587), Vector2(-5787, -692), Vector2(-6446, -1169), Vector2(-7409, -1004), Vector2(-8115, -1233), Vector2(-8890, -1021), Vector2(-9551, -1348), Vector2(-10256, -874), Vector2(-11048, -1153), Vector2(-11149, -1934), Vector2(-10419, -2386)], "w": 290, "rooms": [[4, 389], [6, 340], [8, 404], [11, 340], [14, 429]], "arena": 680},
	"orm_2": {"pts": [Vector2(0, 0), Vector2(-880, 354), Vector2(-1676, 220), Vector2(-2084, -368), Vector2(-2882, -558), Vector2(-3274, -1340), Vector2(-4063, -1445), Vector2(-4677, -1152), Vector2(-5368, -1306), Vector2(-6122, -731), Vector2(-6798, -1066), Vector2(-7597, -1014), Vector2(-8131, -322), Vector2(-8877, -60), Vector2(-9372, 648), Vector2(-10174, 590), Vector2(-10602, 1177), Vector2(-10469, 2025), Vector2(-9800, 2452), Vector2(-9026, 2544), Vector2(-8617, 1885), Vector2(-7742, 1539)], "w": 280, "rooms": [[4, 419], [6, 340], [9, 354], [12, 390], [15, 340], [17, 394]], "arena": 680},
	"mora_0": {"pts": [Vector2(0, 0), Vector2(2, 787), Vector2(-680, 1463), Vector2(-893, 2419), Vector2(-1554, 2981), Vector2(-1664, 3917), Vector2(-2444, 4499), Vector2(-2781, 5343), Vector2(-3505, 5623), Vector2(-4187, 5356), Vector2(-4727, 5781), Vector2(-4619, 6729), Vector2(-4232, 7297), Vector2(-3330, 7390)], "w": 300, "rooms": [[3, 447], [5, 520], [8, 340], [10, 340]], "arena": 680},
	"mora_1": {"pts": [Vector2(0, 0), Vector2(-636, 364), Vector2(-915, 1108), Vector2(-1450, 1529), Vector2(-1694, 2259), Vector2(-2386, 2384), Vector2(-2990, 1671), Vector2(-3731, 1501), Vector2(-4388, 1997), Vector2(-4374, 2746), Vector2(-4832, 3334), Vector2(-4835, 4096), Vector2(-5443, 4437), Vector2(-6144, 4378), Vector2(-6498, 3743), Vector2(-7294, 3388), Vector2(-7971, 3841), Vector2(-7935, 4816), Vector2(-7496, 5360)], "w": 290, "rooms": [[4, 340], [6, 350], [9, 340], [12, 340], [14, 340]], "arena": 680},
	"mora_2": {"pts": [Vector2(0, 0), Vector2(-745, 564), Vector2(-873, 1420), Vector2(-1555, 1774), Vector2(-2281, 1400), Vector2(-3055, 1410), Vector2(-3396, 743), Vector2(-4250, 433), Vector2(-4924, 821), Vector2(-5669, 827), Vector2(-6284, 447), Vector2(-7070, 650), Vector2(-7425, 1361), Vector2(-7230, 2075), Vector2(-7746, 2886), Vector2(-7662, 3734), Vector2(-8148, 4371), Vector2(-8063, 5337), Vector2(-8686, 5775), Vector2(-8878, 6484), Vector2(-9604, 6662), Vector2(-9927, 7422)], "w": 280, "rooms": [[4, 373], [6, 349], [9, 340], [12, 340], [15, 401], [17, 362]], "arena": 680},
	"zephyr_0": {"pts": [Vector2(0, 0), Vector2(881, -9), Vector2(1655, -570), Vector2(2415, -393), Vector2(3079, -599), Vector2(3206, -1361), Vector2(3791, -1719), Vector2(3761, -2570), Vector2(4210, -3281), Vector2(5063, -3563), Vector2(5721, -2963), Vector2(6404, -2924), Vector2(6774, -2047), Vector2(7509, -1776)], "w": 300, "rooms": [[3, 340], [5, 340], [8, 419], [10, 340]], "arena": 680},
	"zephyr_1": {"pts": [Vector2(0, 0), Vector2(-602, 530), Vector2(-1363, 463), Vector2(-1970, 1101), Vector2(-2707, 1323), Vector2(-3081, 1920), Vector2(-2796, 2617), Vector2(-2909, 3533), Vector2(-3469, 4239), Vector2(-3223, 4995), Vector2(-3585, 5573), Vector2(-4447, 5824), Vector2(-5358, 5578), Vector2(-6031, 5899), Vector2(-6051, 6614), Vector2(-5681, 7191), Vector2(-5704, 7897), Vector2(-5169, 8579)], "w": 290, "rooms": [[4, 340], [6, 342], [8, 385], [11, 487], [14, 340]], "arena": 680},
	"zephyr_2": {"pts": [Vector2(0, 0), Vector2(477, 614), Vector2(1340, 902), Vector2(1970, 468), Vector2(2709, 802), Vector2(2735, 1641), Vector2(2004, 2195), Vector2(2167, 2965), Vector2(1680, 3569), Vector2(2028, 4293), Vector2(2739, 4555), Vector2(3334, 5328), Vector2(4231, 5488), Vector2(4969, 6117), Vector2(4923, 6958), Vector2(4519, 7566), Vector2(4574, 8307), Vector2(4007, 8985), Vector2(4009, 9917), Vector2(3309, 10355), Vector2(3241, 11113)], "w": 280, "rooms": [[4, 410], [6, 387], [9, 358], [11, 511], [14, 340], [16, 342]], "arena": 680},
	"iris_0": {"pts": [Vector2(0, 0), Vector2(717, 607), Vector2(1635, 611), Vector2(2252, -118), Vector2(3084, -82), Vector2(3442, -697), Vector2(4224, -882), Vector2(4962, -341), Vector2(5919, -174), Vector2(6777, -512), Vector2(7348, -1268), Vector2(7964, -1560), Vector2(8672, -1254), Vector2(9327, -1679)], "w": 300, "rooms": [[3, 412], [5, 340], [8, 502], [10, 340]], "arena": 680},
	"iris_1": {"pts": [Vector2(0, 0), Vector2(-136, -902), Vector2(203, -1561), Vector2(1164, -1570), Vector2(1795, -2010), Vector2(1884, -2893), Vector2(2447, -3597), Vector2(3150, -3489), Vector2(3552, -2614), Vector2(4306, -2206), Vector2(5152, -2211), Vector2(5815, -2743), Vector2(5735, -3481), Vector2(6395, -4055), Vector2(6230, -4753), Vector2(5327, -5021), Vector2(4416, -4689)], "w": 290, "rooms": [[3, 359], [6, 340], [8, 447], [10, 436], [13, 340]], "arena": 680},
	"iris_2": {"pts": [Vector2(0, 0), Vector2(475, -598), Vector2(1288, -660), Vector2(2042, -1164), Vector2(2728, -935), Vector2(3018, -82), Vector2(3790, 483), Vector2(4461, 178), Vector2(5198, 450), Vector2(6117, 197), Vector2(6329, -742), Vector2(6920, -1283), Vector2(7139, -2070), Vector2(7665, -2552), Vector2(7643, -3309), Vector2(8154, -3792), Vector2(7976, -4756), Vector2(8204, -5526), Vector2(7977, -6238), Vector2(7227, -6373), Vector2(6726, -7155)], "w": 280, "rooms": [[4, 340], [6, 340], [9, 520], [11, 401], [14, 340], [16, 402]], "arena": 680},
	"lyra_0": {"pts": [Vector2(0, 0), Vector2(307, 926), Vector2(-208, 1593), Vector2(-146, 2517), Vector2(-654, 3223), Vector2(-315, 4000), Vector2(-878, 4776), Vector2(-908, 5546), Vector2(-1321, 6107), Vector2(-1206, 7043), Vector2(-1593, 7931), Vector2(-1197, 8794), Vector2(-501, 8808), Vector2(-31, 9500)], "w": 300, "rooms": [[3, 450], [5, 428], [8, 340], [10, 520]], "arena": 680},
	"lyra_1": {"pts": [Vector2(0, 0), Vector2(-593, -599), Vector2(-1264, -770), Vector2(-1951, -535), Vector2(-2623, -1205), Vector2(-3353, -1256), Vector2(-3737, -1854), Vector2(-4409, -2247), Vector2(-4494, -3032), Vector2(-3814, -3696), Vector2(-3765, -4672), Vector2(-4528, -5156), Vector2(-5309, -4982), Vector2(-6090, -5227), Vector2(-6541, -5791), Vector2(-7283, -5913), Vector2(-7494, -6615), Vector2(-8333, -6904)], "w": 290, "rooms": [[4, 340], [6, 340], [8, 379], [11, 389], [14, 340]], "arena": 680},
	"lyra_2": {"pts": [Vector2(0, 0), Vector2(877, -375), Vector2(956, -1107), Vector2(1406, -1784), Vector2(1170, -2581), Vector2(1690, -3282), Vector2(2598, -3428), Vector2(3407, -3070), Vector2(3915, -2280), Vector2(4830, -1969), Vector2(5571, -2369), Vector2(5533, -3337), Vector2(6016, -4103), Vector2(6806, -4157), Vector2(7295, -3327), Vector2(8076, -3322), Vector2(8556, -2758), Vector2(9293, -2480), Vector2(10057, -3023), Vector2(10659, -2675), Vector2(11362, -2855)], "w": 280, "rooms": [[4, 430], [6, 483], [9, 441], [11, 505], [14, 381], [16, 340]], "arena": 680},
	"sol_0": {"pts": [Vector2(0, 0), Vector2(-407, 578), Vector2(-1083, 473), Vector2(-1660, 913), Vector2(-2415, 989), Vector2(-2999, 1390), Vector2(-2936, 2106), Vector2(-3519, 2812), Vector2(-3319, 3716), Vector2(-3807, 4328), Vector2(-3568, 4975), Vector2(-4099, 5594), Vector2(-3793, 6375), Vector2(-4219, 7240), Vector2(-5070, 7708)], "w": 300, "rooms": [[3, 340], [6, 340], [8, 362], [11, 395]], "arena": 680},
	"sol_1": {"pts": [Vector2(0, 0), Vector2(273, 742), Vector2(980, 1108), Vector2(1315, 1712), Vector2(2238, 1894), Vector2(2685, 2472), Vector2(3517, 2278), Vector2(4031, 1722), Vector2(4812, 1640), Vector2(5536, 2184), Vector2(6464, 2330), Vector2(7009, 2946), Vector2(7058, 3821), Vector2(6378, 4187), Vector2(6366, 4962), Vector2(5590, 5513), Vector2(5587, 6260), Vector2(6190, 6902)], "w": 290, "rooms": [[4, 340], [6, 348], [8, 374], [11, 411], [14, 365]], "arena": 680},
	"sol_2": {"pts": [Vector2(0, 0), Vector2(760, 232), Vector2(1515, -17), Vector2(1669, -751), Vector2(2266, -1262), Vector2(3233, -1287), Vector2(3733, -609), Vector2(3370, 85), Vector2(3725, 719), Vector2(4333, 1062), Vector2(4649, 1758), Vector2(4476, 2606), Vector2(4744, 3354), Vector2(5477, 3568), Vector2(6273, 3263), Vector2(6343, 2558), Vector2(6791, 1884), Vector2(7514, 1761), Vector2(7996, 2306), Vector2(8802, 2083), Vector2(9128, 1423), Vector2(9890, 1358), Vector2(10160, 732)], "w": 280, "rooms": [[4, 385], [7, 340], [10, 364], [12, 364], [15, 340], [18, 340]], "arena": 680},
	"volt_0": {"pts": [Vector2(0, 0), Vector2(-345, -661), Vector2(-249, -1439), Vector2(279, -2043), Vector2(104, -2847), Vector2(571, -3540), Vector2(522, -4435), Vector2(1143, -4807), Vector2(1259, -5513), Vector2(888, -6324), Vector2(1146, -7035), Vector2(1740, -7376), Vector2(2433, -7294), Vector2(3071, -8034), Vector2(2850, -8806)], "w": 300, "rooms": [[3, 383], [6, 340], [8, 340], [11, 340]], "arena": 680},
	"volt_1": {"pts": [Vector2(0, 0), Vector2(862, 155), Vector2(1493, 836), Vector2(1462, 1704), Vector2(2040, 2476), Vector2(1800, 3125), Vector2(2149, 3780), Vector2(2784, 4238), Vector2(3469, 4350), Vector2(3993, 3707), Vector2(4842, 3887), Vector2(5681, 3554), Vector2(6357, 4112), Vector2(7152, 4191), Vector2(7450, 5055), Vector2(8000, 5499), Vector2(8731, 5491), Vector2(9048, 4764)], "w": 290, "rooms": [[4, 340], [6, 340], [8, 340], [11, 466], [14, 340]], "arena": 680},
	"volt_2": {"pts": [Vector2(0, 0), Vector2(-530, -548), Vector2(-646, -1230), Vector2(-1433, -1767), Vector2(-1676, -2629), Vector2(-1172, -3263), Vector2(-1233, -3990), Vector2(-1959, -4393), Vector2(-2366, -5027), Vector2(-3234, -4923), Vector2(-3715, -5703), Vector2(-4490, -6010), Vector2(-5309, -5759), Vector2(-6065, -6143), Vector2(-6093, -6996), Vector2(-6889, -7435), Vector2(-6851, -8290), Vector2(-7475, -8621), Vector2(-8014, -9367), Vector2(-8698, -9489), Vector2(-9315, -10058)], "w": 280, "rooms": [[4, 410], [6, 340], [9, 474], [11, 433], [14, 453], [16, 340]], "arena": 680},
	"kai_0": {"pts": [Vector2(0, 0), Vector2(-551, -714), Vector2(-208, -1443), Vector2(-655, -2162), Vector2(-573, -3002), Vector2(-955, -3741), Vector2(-696, -4411), Vector2(-795, -5094), Vector2(-1561, -5557), Vector2(-1639, -6276), Vector2(-2076, -6872), Vector2(-2969, -6705), Vector2(-3619, -7330), Vector2(-4548, -7302)], "w": 300, "rooms": [[3, 423], [5, 340], [8, 340], [10, 340]], "arena": 680},
	"kai_1": {"pts": [Vector2(0, 0), Vector2(-860, 334), Vector2(-1510, -131), Vector2(-2441, -12), Vector2(-3127, -520), Vector2(-3952, -441), Vector2(-4551, 313), Vector2(-5260, 449), Vector2(-5445, 1164), Vector2(-6373, 1348), Vector2(-6938, 1965), Vector2(-6755, 2917), Vector2(-7119, 3763), Vector2(-7939, 4241), Vector2(-8321, 5064), Vector2(-9023, 5637), Vector2(-8971, 6338)], "w": 290, "rooms": [[3, 442], [6, 340], [8, 340], [10, 425], [13, 497]], "arena": 680},
	"kai_2": {"pts": [Vector2(0, 0), Vector2(-630, -519), Vector2(-764, -1208), Vector2(-1291, -1848), Vector2(-2039, -2049), Vector2(-2909, -1777), Vector2(-3686, -2059), Vector2(-4147, -2633), Vector2(-4838, -2779), Vector2(-5444, -3316), Vector2(-5591, -4225), Vector2(-6190, -4840), Vector2(-6976, -4566), Vector2(-7575, -4951), Vector2(-7919, -5730), Vector2(-7373, -6537), Vector2(-7248, -7440), Vector2(-7660, -8222), Vector2(-8507, -8564), Vector2(-9309, -8150), Vector2(-9783, -7367)], "w": 280, "rooms": [[4, 374], [6, 340], [9, 409], [11, 432], [14, 451], [16, 484]], "arena": 680},
}

var hero := ""
var step := 0
var pts: Array = []
var w := 300.0
var rooms: Array = []      # [индекс точки, радиус]
var arena_r := 680.0
var cum: Array = []        # длина пути до каждой точки
var total := 0.0
var locked := false        # арена запечатана: бой с владыкой
var _shapes: Array = []    # ["c", центр, r] / ["s", a, b, w]
var _place := {}           # чанк -> [[pos, kind, rot, light], ...]


static func for_level(i: int):
	if not HeroCh.is_hero_level(i):
		return null
	var key := "%s_%d" % [HeroCh.hero_of(i), HeroCh.step_of(i)]
	if not MAPS.has(key):
		return null
	var m = load("res://scripts/chapter_map.gd").new()
	m._setup(HeroCh.hero_of(i), HeroCh.step_of(i), MAPS[key])
	return m


func _setup(h: String, st: int, d: Dictionary) -> void:
	hero = h
	step = st
	pts = d["pts"]
	w = float(d["w"])
	rooms = d["rooms"]
	arena_r = float(d["arena"])
	cum = [0.0]
	for i in range(1, pts.size()):
		cum.append(float(cum[-1]) + (pts[i] - pts[i - 1]).length())
	total = cum[-1]
	for i in range(pts.size() - 1):
		_shapes.append(["s", pts[i], pts[i + 1], w])
	_shapes.append(["c", pts[0], w])
	for r in rooms:
		_shapes.append(["c", pts[int(r[0])], float(r[1])])
	_shapes.append(["c", arena_center(), arena_r])
	_build_layout()


func arena_center() -> Vector2:
	return pts[-1]


func room_center(k: int) -> Vector2:
	return pts[int(rooms[k][0])]


func room_radius(k: int) -> float:
	return float(rooms[k][1])


# ---------------- Геометрия ----------------

static func _closest_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


func _sd_shape(p: Vector2, s: Array) -> float:
	if s[0] == "c":
		return p.distance_to(s[1]) - float(s[2])
	return p.distance_to(_closest_on_seg(p, s[1], s[2])) - float(s[3])


## Расстояние со знаком до края карты (меньше нуля — внутри).
func sd(p: Vector2) -> float:
	if locked:
		return p.distance_to(arena_center()) - arena_r
	var best := INF
	for s in _shapes:
		best = minf(best, _sd_shape(p, s))
	return best


func inside(p: Vector2, margin := 0.0) -> bool:
	return sd(p) <= -margin


## Удержать круг радиуса r внутри карты.
func clamp_pos(p: Vector2, r: float) -> Vector2:
	if locked:
		var c := arena_center()
		var lim := maxf(arena_r - r, 0.0)
		var d := p - c
		return p if d.length() <= lim else c + d.normalized() * lim
	var best := INF
	var bs: Array = []
	for s in _shapes:
		var v := _sd_shape(p, s)
		if v < best:
			best = v
			bs = s
		if v <= -r:
			return p
	var q: Vector2 = bs[1] if bs[0] == "c" else _closest_on_seg(p, bs[1], bs[2])
	var lim2: float = maxf(float(bs[2] if bs[0] == "c" else bs[3]) - r, 0.0)
	var dd := p - q
	if dd.length() < 0.01:
		return q
	return q + dd.normalized() * lim2


## Пройденная часть пути (по ближайшей точке на линии пути).
func progress(p: Vector2) -> float:
	var best := INF
	var out := 0.0
	for i in range(pts.size() - 1):
		var q := _closest_on_seg(p, pts[i], pts[i + 1])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			out = float(cum[i]) + q.distance_to(pts[i])
	return out


func point_at(s: float) -> Vector2:
	s = clampf(s, 0.0, total)
	for i in range(pts.size() - 1):
		if s <= float(cum[i + 1]) or i == pts.size() - 2:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			return a + (b - a).normalized() * (s - float(cum[i]))
	return pts[-1]


func dir_at(s: float) -> Vector2:
	s = clampf(s, 0.0, total)
	for i in range(pts.size() - 1):
		if s <= float(cum[i + 1]) or i == pts.size() - 2:
			return (pts[i + 1] - pts[i]).normalized()
	return Vector2.RIGHT


## Точка появления врага: вдоль пути впереди или позади героя, вне его взгляда в упор.
func spawn_point(anchor: Vector2, rng: RandomNumberGenerator, avoid: Array) -> Vector2:
	if locked:
		for t in 6:
			var p := arena_center() + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(arena_r * 0.55, arena_r - 40.0)
			if _far(p, avoid, 330.0):
				return p
		return arena_center() + Vector2.RIGHT.rotated(rng.randf() * TAU) * (arena_r - 40.0)
	var s0 := progress(anchor)
	var p2 := anchor
	for t in 6:
		var sgn := 1.0 if rng.randf() < 0.65 else -1.0
		var s := s0 + sgn * rng.randf_range(520.0, 900.0)
		if s < 0.0 or s > total:
			s = s0 - sgn * rng.randf_range(520.0, 900.0)
		s = clampf(s, 0.0, total)
		var d := dir_at(s)
		p2 = point_at(s) + d.orthogonal() * rng.randf_range(-0.7, 0.7) * w
		if _far(p2, avoid, 420.0):
			return p2
	return p2


static func _far(p: Vector2, avoid: Array, r: float) -> bool:
	for a in avoid:
		if p.distance_to(a) < r:
			return false
	return true


# ---------------- Стены и убранство (один раз, неизменно) ----------------

func _kind(k: String) -> String:
	return "c_%s_%s" % [hero, k]


func _add_place(p: Vector2, kind: String, rot: float, light := false) -> void:
	var key := Vector2i(floori(p.x / 768.0), floori(p.y / 768.0))
	if not _place.has(key):
		_place[key] = []
	_place[key].append([p, kind, rot, light])


func _ring_row(off: float, min_sd: float, spacing: float, kinds: Array, light_every: int) -> void:
	var acc: Array = []
	var n := 0
	for s in _shapes:
		var cands: Array = []
		if s[0] == "s":
			var a: Vector2 = s[1]
			var b: Vector2 = s[2]
			var dir := (b - a).normalized()
			var ln := a.distance_to(b)
			var cnt := maxi(1, int(ln / spacing))
			for i in cnt + 1:
				var c := a + dir * (ln * i / cnt)
				for sg in [-1.0, 1.0]:
					cands.append([c + dir.orthogonal() * sg * (float(s[3]) + off), -dir.angle()])
		else:
			var rr: float = float(s[2]) + off
			var cnt2 := maxi(6, int(TAU * rr / spacing))
			for i in cnt2:
				var an := TAU * i / cnt2
				cands.append([s[1] + Vector2.RIGHT.rotated(an) * rr, -(an + PI / 2.0)])
		for c in cands:
			var p: Vector2 = c[0]
			var lock_save := locked
			locked = false
			var v := sd(p)
			locked = lock_save
			if v < min_sd:
				continue
			var near := false
			for q in acc:
				if p.distance_squared_to(q) < spacing * spacing * 0.55:
					near = true
					break
			if near:
				continue
			acc.append(p)
			n += 1
			var kind: String = kinds[n % kinds.size()]
			_add_place(p, kind, c[1], light_every > 0 and n % light_every == 0)


func _build_layout() -> void:
	# Три ряда: стена вплотную к краю, за ней крупные объекты, дальше — плотная чаща
	_ring_row(55.0, 35.0, 125.0, [_kind("w"), _kind("w"), _kind("w"), _kind("b")], 7)
	_ring_row(210.0, 150.0, 175.0, [_kind("b"), _kind("w")], 0)
	_ring_row(380.0, 300.0, 230.0, [_kind("b")], 0)
	# Убранство внутри: у стен коридора и по краю залов
	var k := 0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dir := (b - a).normalized()
		var ln := a.distance_to(b)
		var cnt := int(ln / 520.0)
		for j in cnt:
			k += 1
			var p := a + dir * (ln * (j + 0.5) / cnt) + dir.orthogonal() * (w - 55.0) * (1.0 if k % 2 == 0 else -1.0)
			if p.distance_to(pts[0]) > 260.0:
				_add_place(p, _kind("d"), -dir.angle(), k % 3 == 0)
	for r in rooms:
		var c: Vector2 = pts[int(r[0])]
		var rr := float(r[1]) - 70.0
		for j in 5:
			var an := TAU * j / 5.0 + 0.4
			var p := c + Vector2.RIGHT.rotated(an) * rr
			_add_place(p, _kind("d"), -an, j == 0)
	var ac := arena_center()
	for j in 8:
		var an := TAU * j / 8.0
		_add_place(ac + Vector2.RIGHT.rotated(an) * (arena_r - 60.0), _kind("d"), -an, j % 2 == 0)


func placements(key: Vector2i) -> Array:
	return _place.get(key, [])
