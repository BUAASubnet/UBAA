课表相关API
/api/v1/schedule/
以下提供上游api，中转api由自己设计实现

首先访问https://byxt.buaa.edu.cn进行认证

获取学期
GET https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do
返回值：
{
    "datas": [
        {
            "itemCode": "2024-2025-1",
            "itemName": "2024秋季",
            "selected": false,
            "itemIndex": 1
        },
        {
            "itemCode": "2024-2025-2",
            "itemName": "2025春季",
            "selected": false,
            "itemIndex": 2
        },
        {
            "itemCode": "2024-2025-3",
            "itemName": "2025夏季",
            "selected": false,
            "itemIndex": 3
        },
        {
            "itemCode": "2025-2026-1",
            "itemName": "2025秋季",
            "selected": true,
            "itemIndex": 4
        },
        {
            "itemCode": "2025-2026-2",
            "itemName": "2026春季",
            "selected": false,
            "itemIndex": 5
        },
        {
            "itemCode": "2026-2027-2",
            "itemName": "2027春季",
            "selected": false,
            "itemIndex": 6
        }
    ],
    "code": "0",
    "msg": null
}

获取周数
GET https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do?termCode=2025-2026-1
返回值：
{
    "datas": [
        {
            "endDate": "2025-09-14 00:00:00",
            "startDate": "2025-09-08 00:00:00",
            "term": "2025-2026-1",
            "curWeek": false,
            "serialNumber": 1,
            "name": "第1周"
        },
        {
            "endDate": "2025-09-21 00:00:00",
            "startDate": "2025-09-15 00:00:00",
            "term": "2025-2026-1",
            "curWeek": false,
            "serialNumber": 2,
            "name": "第2周"
        },
        ......(中间省略)
        {
            "endDate": "2026-01-18 00:00:00",
            "startDate": "2026-01-12 00:00:00",
            "term": "2025-2026-1",
            "curWeek": false,
            "serialNumber": 19,
            "name": "第19周"
        }
    ],
    "code": "0",
    "msg": null
}

获取周课表
POST https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do
请求体：
termCode=2025-2026-1&campusCode=&type=week&week=3
返回值：
{
    "datas": {
        "arrangedList": [
            {
                "week": null,
                "beginTime": "08:00",
                "byCode": "0",
                "endTime": "09:35",
                "beginSection": 1,
                "endSection": 2,
                "courseCode": "B310023003",
                "courseSerialNo": "012",
                "teachClassName": null,
                "teachingTarget": "242113，242114，242115，242111，242112，240291，241811，241821，240214，240215，240211，240213，240212，240222，240221，2024级具身智能机器人项目制专业机器人工程",
                "weeksAndTeachers": "1-16周[理论]\/王菁菁[主讲]",
                "placeName": "篮球场",
                "teachClassId": "202520261B310023003012",
                "cellDetail": [
                    {
                        "text": "（本）体育（3）",
                        "color": null
                    },
                    {
                        "text": "【篮球1】",
                        "color": null
                    },
                    {
                        "text": "王菁菁[1-16周]",
                        "color": null
                    },
                    {
                        "text": "篮球场",
                        "color": null
                    },
                    {
                        "text": "1-2节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "体育项目：篮球1",
                    "课程号：B310023003",
                    "课程名：体育（3）",
                    "课序号：012",
                    "上课教师：王菁菁\/1-2节",
                    "上课地点：学院路校区\/运动场地\/篮球场"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "体育（3）",
                "credit": "0.5",
                "color": "#FFF0CC",
                "dayOfWeek": 1
            },
            {
                "week": null,
                "beginTime": "08:00",
                "byCode": "0",
                "endTime": "09:35",
                "beginSection": 1,
                "endSection": 2,
                "courseCode": "B210031004",
                "courseSerialNo": "002",
                "teachClassName": null,
                "teachingTarget": "252101，242115，242113，242114，241811，242111，242112",
                "weeksAndTeachers": "1-17周[理论]\/罗川[主讲]",
                "placeName": "主南205",
                "teachClassId": "202520261B210031004002",
                "cellDetail": [
                    {
                        "text": "（本）算法分析与设计",
                        "color": null
                    },
                    {
                        "text": "罗川[1-17周]",
                        "color": null
                    },
                    {
                        "text": "主南205",
                        "color": null
                    },
                    {
                        "text": "1-2节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031004",
                    "课程名：算法分析与设计",
                    "课序号：002",
                    "上课教师：罗川\/1-2节",
                    "上课地点：学院路校区\/主楼\/主南205"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "算法分析与设计",
                "credit": "3.0",
                "color": "#FFDDD3",
                "dayOfWeek": 3
            },
            {
                "week": null,
                "beginTime": "09:50",
                "byCode": "0",
                "endTime": "11:25",
                "beginSection": 3,
                "endSection": 4,
                "courseCode": "B210031003",
                "courseSerialNo": "002",
                "teachClassName": null,
                "teachingTarget": "242112，242111，242114，242113，242115，252101，241811",
                "weeksAndTeachers": "1-4周,6周[理论]\/张梦豪[主讲]",
                "placeName": "主M101",
                "teachClassId": "202520261B210031003002",
                "cellDetail": [
                    {
                        "text": "（本）离散数学（2）",
                        "color": null
                    },
                    {
                        "text": "张梦豪[1-4周,6周]",
                        "color": null
                    },
                    {
                        "text": "主M101",
                        "color": null
                    },
                    {
                        "text": "3-4节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031003",
                    "课程名：离散数学（2）",
                    "课序号：002",
                    "上课教师：张梦豪\/3-4节",
                    "上课地点：学院路校区\/主楼\/主M101"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "离散数学（2）",
                "credit": "2.0",
                "color": "#FFDDD3",
                "dayOfWeek": 2
            },
            {
                "week": null,
                "beginTime": "09:50",
                "byCode": "0",
                "endTime": "12:15",
                "beginSection": 3,
                "endSection": 5,
                "courseCode": "B090011018",
                "courseSerialNo": "001",
                "teachClassName": null,
                "teachingTarget": "241811，242114，242115，242112，242111，242113",
                "weeksAndTeachers": "1-16周[理论]\/张思容[主讲]",
                "placeName": "(三)205",
                "teachClassId": "202520261B090011018001",
                "cellDetail": [
                    {
                        "text": "（本）概率统计A",
                        "color": null
                    },
                    {
                        "text": "张思容[1-16周]",
                        "color": null
                    },
                    {
                        "text": "(三)205",
                        "color": null
                    },
                    {
                        "text": "3-5节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B090011018",
                    "课程名：概率统计A",
                    "课序号：001",
                    "上课教师：张思容\/3-5节",
                    "上课地点：学院路校区\/三号楼\/(三)205"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "概率统计A",
                "credit": "3.0",
                "color": "#D3EAFD",
                "dayOfWeek": 3
            },
            {
                "week": null,
                "beginTime": "09:50",
                "byCode": "0",
                "endTime": "11:25",
                "beginSection": 3,
                "endSection": 4,
                "courseCode": "B120013007",
                "courseSerialNo": "067",
                "teachClassName": null,
                "teachingTarget": "2024级金融学金融工程，242115，240811，240891，240831，240821，240851，2024级具身智能机器人项目制专业自动化，240312，240311，240322，240323，240324，240325，240331，240321，244512，240892，241811，242614，242611，242612，242613，242114，2024级金融学金融科技",
                "weeksAndTeachers": "1-3周,5-9周[理论]\/王晨爽[主讲]",
                "placeName": "F222",
                "teachClassId": "202520261B120013007067",
                "cellDetail": [
                    {
                        "text": "（本）英语阅读（3）",
                        "color": null
                    },
                    {
                        "text": "王晨爽[1-3周,5-9周]",
                        "color": null
                    },
                    {
                        "text": "F222",
                        "color": null
                    },
                    {
                        "text": "3-4节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B120013007",
                    "课程名：英语阅读（3）",
                    "课序号：067",
                    "上课教师：王晨爽\/3-4节",
                    "上课地点：学院路校区\/新主楼\/F222"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "英语阅读（3）",
                "credit": "1.0",
                "color": "#D3F4F8",
                "dayOfWeek": 4
            },
            {
                "week": null,
                "beginTime": "14:00",
                "byCode": "0",
                "endTime": "15:35",
                "beginSection": 6,
                "endSection": 7,
                "courseCode": "B210031002",
                "courseSerialNo": "001",
                "teachClassName": null,
                "teachingTarget": "252101，242115，242113，242114，242111，242112，241811",
                "weeksAndTeachers": "1-4周,6-15周[理论]\/刘子鹏[主讲]",
                "placeName": "主南203",
                "teachClassId": "202520261B210031002001",
                "cellDetail": [
                    {
                        "text": "（本）计算机硬件基础（软件专业）",
                        "color": null
                    },
                    {
                        "text": "刘子鹏[1-4周,6-15周]",
                        "color": null
                    },
                    {
                        "text": "主南203",
                        "color": null
                    },
                    {
                        "text": "6-7节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031002",
                    "课程名：计算机硬件基础（软件专业）",
                    "课序号：001",
                    "上课教师：刘子鹏\/6-7节",
                    "上课地点：学院路校区\/主楼\/主南203"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "计算机硬件基础（软件专业）",
                "credit": "4.0",
                "color": "#D3EAFD",
                "dayOfWeek": 1
            },
            {
                "week": null,
                "beginTime": "14:00",
                "byCode": "0",
                "endTime": "17:25",
                "beginSection": 6,
                "endSection": 9,
                "courseCode": "B190011007",
                "courseSerialNo": "005",
                "teachClassName": null,
                "teachingTarget": "241811，242114，242115，242111，242112，242113",
                "weeksAndTeachers": "1-16周[实验]\/徐平[主讲]",
                "placeName": "物理教学与实验中心",
                "teachClassId": "202520261B190011007005",
                "cellDetail": [
                    {
                        "text": "（本）基础物理实验(1)",
                        "color": null
                    },
                    {
                        "text": "徐平[1-16周]",
                        "color": null
                    },
                    {
                        "text": "物理教学与实验中心",
                        "color": null
                    },
                    {
                        "text": "6-9节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B190011007",
                    "课程名：基础物理实验(1)",
                    "课序号：005",
                    "上课教师：徐平\/6-9节",
                    "上课地点：学院路校区\/本校区场地\/物理教学与实验中心"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "基础物理实验(1)",
                "credit": "1.0",
                "color": "#E8F3DB",
                "dayOfWeek": 2
            },
            {
                "week": null,
                "beginTime": "14:00",
                "byCode": "0",
                "endTime": "15:35",
                "beginSection": 6,
                "endSection": 7,
                "courseCode": "B210031002",
                "courseSerialNo": "001",
                "teachClassName": null,
                "teachingTarget": "252101，242115，242113，242114，242111，242112，241811",
                "weeksAndTeachers": "1-3周,5-15周[理论]\/刘子鹏[主讲]",
                "placeName": "主南203",
                "teachClassId": "202520261B210031002001",
                "cellDetail": [
                    {
                        "text": "（本）计算机硬件基础（软件专业）",
                        "color": null
                    },
                    {
                        "text": "刘子鹏[1-3周,5-15周]",
                        "color": null
                    },
                    {
                        "text": "主南203",
                        "color": null
                    },
                    {
                        "text": "6-7节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031002",
                    "课程名：计算机硬件基础（软件专业）",
                    "课序号：001",
                    "上课教师：刘子鹏\/6-7节",
                    "上课地点：学院路校区\/主楼\/主南203"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "计算机硬件基础（软件专业）",
                "credit": "4.0",
                "color": "#D3EAFD",
                "dayOfWeek": 5
            },
            {
                "week": null,
                "beginTime": "15:50",
                "byCode": "0",
                "endTime": "17:25",
                "beginSection": 8,
                "endSection": 9,
                "courseCode": "B210031001",
                "courseSerialNo": "002",
                "teachClassName": null,
                "teachingTarget": "242111，242114，242113，242115，252101，241811，242112",
                "weeksAndTeachers": "1-3周,5-17周[理论]\/高祥[主讲]",
                "placeName": "主南305",
                "teachClassId": "202520261B210031001002",
                "cellDetail": [
                    {
                        "text": "（本）面向对象程序设计（JAVA）",
                        "color": null
                    },
                    {
                        "text": "高祥[1-3周,5-17周]",
                        "color": null
                    },
                    {
                        "text": "主南305",
                        "color": null
                    },
                    {
                        "text": "8-9节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031001",
                    "课程名：面向对象程序设计（JAVA）",
                    "课序号：002",
                    "上课教师：高祥\/8-9节",
                    "上课地点：学院路校区\/主楼\/主南305"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "面向对象程序设计（JAVA）",
                "credit": "2.5",
                "color": "#FFDDD3",
                "dayOfWeek": 4
            },
            {
                "week": null,
                "beginTime": "15:50",
                "byCode": "0",
                "endTime": "18:15",
                "beginSection": 8,
                "endSection": 10,
                "courseCode": "B280021004",
                "courseSerialNo": "029",
                "teachClassName": null,
                "teachingTarget": "242114，241811，242115，242111，242112，242113",
                "weeksAndTeachers": "1-16周[理论]\/裴振磊[主讲]",
                "placeName": "(三)205",
                "teachClassId": "202520261B280021004029",
                "cellDetail": [
                    {
                        "text": "（本）毛泽东思想和中国特色社会主义理论体系概论",
                        "color": null
                    },
                    {
                        "text": "裴振磊[1-16周]",
                        "color": null
                    },
                    {
                        "text": "(三)205",
                        "color": null
                    },
                    {
                        "text": "8-10节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B280021004",
                    "课程名：毛泽东思想和中国特色社会主义理论体系概论",
                    "课序号：029",
                    "上课教师：裴振磊\/8-10节",
                    "上课地点：学院路校区\/三号楼\/(三)205"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "毛泽东思想和中国特色社会主义理论体系概论",
                "credit": "3.0",
                "color": "#DDE4FE",
                "dayOfWeek": 5
            },
            {
                "week": null,
                "beginTime": "19:00",
                "byCode": "0",
                "endTime": "20:35",
                "beginSection": 11,
                "endSection": 12,
                "courseCode": "B210031004",
                "courseSerialNo": "002",
                "teachClassName": null,
                "teachingTarget": "252101，242115，242113，242114，241811，242111，242112",
                "weeksAndTeachers": "2-17周[实验]\/罗川[主讲]",
                "placeName": null,
                "teachClassId": "202520261B210031004002",
                "cellDetail": [
                    {
                        "text": "（本）算法分析与设计",
                        "color": null
                    },
                    {
                        "text": "罗川[2-17周]",
                        "color": null
                    },
                    {
                        "text": "",
                        "color": null
                    },
                    {
                        "text": "11-12节",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：B210031004",
                    "课程名：算法分析与设计",
                    "课序号：002",
                    "上课教师：罗川\/11-12节"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "算法分析与设计",
                "credit": "3.0",
                "color": "#FFDDD3",
                "dayOfWeek": 3
            },
            {
                "week": null,
                "beginTime": null,
                "byCode": "0",
                "endTime": null,
                "beginSection": 6,
                "endSection": 9,
                "courseCode": "B190011007",
                "courseSerialNo": null,
                "teachClassName": null,
                "teachingTarget": null,
                "weeksAndTeachers": null,
                "placeName": "物理教学与实验中心（学生13公寓B1-042A）【学生13公寓】",
                "teachClassId": "2025-2026-1-B190011007-005-B19001100701-2",
                "cellDetail": [
                    {
                        "text": "（本【实验课】）基础物理实验(1)",
                        "color": null
                    },
                    {
                        "text": "严琪琪,巴子钰[3周]",
                        "color": null
                    },
                    {
                        "text": "物理教学与实验中心（学生13公寓B1-042A）【学生13公寓】",
                        "color": null
                    },
                    {
                        "text": "6-9节",
                        "color": null
                    },
                    {
                        "text": "电阻—学院路",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本【实验课】",
                    "课程号：B190011007",
                    "课程名：基础物理实验(1)",
                    "上课教师：严琪琪,巴子钰[3周]",
                    "校区：学院路校区",
                    "上课地点：物理教学与实验中心（学生13公寓B1-042A）【学生13公寓】",
                    "实验项目名称：电阻—学院路"
                ],
                "tags": [
                    {
                        "text": "本【实验课】",
                        "color": ""
                    }
                ],
                "multiCourse": null,
                "courseName": "基础物理实验(1)",
                "credit": null,
                "color": "#FCE0EA",
                "dayOfWeek": 2
            }
        ],
        "notArrangeList": [
            {
                "week": null,
                "beginTime": "",
                "byCode": "0",
                "endTime": "",
                "beginSection": null,
                "endSection": null,
                "courseCode": "BA20025003",
                "courseSerialNo": "037",
                "teachClassName": null,
                "teachingTarget": "241821，241811，241861，241891",
                "weeksAndTeachers": "1-16周[实践]\/吴衍川[主讲]",
                "placeName": null,
                "teachClassId": "202520261BA20025003037",
                "cellDetail": [
                    {
                        "text": "（本）素质教育（博雅课程）（3）",
                        "color": null
                    },
                    {
                        "text": "吴衍川[1-16周]",
                        "color": null
                    },
                    {
                        "text": "",
                        "color": null
                    }
                ],
                "titleDetail": [
                    "本研标识：本",
                    "课程号：BA20025003",
                    "课程名：素质教育（博雅课程）（3）",
                    "课序号：037",
                    "上课教师：吴衍川"
                ],
                "tags": [],
                "multiCourse": null,
                "courseName": "素质教育（博雅课程）（3）",
                "credit": "0.2",
                "color": null,
                "dayOfWeek": null
            }
        ],
        "practiceList": [],
        "code": "24182104",
        "name": "李沐衡[24182104]"
    },
    "code": "0",
    "msg": null
}

获取今日课表
GET https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do?rq=2025-09-26&lxdm=student
返回值：
{
    "datas": [
        {
            "bizKey": "SKKC",
            "place": "三号楼(三)205",
            "bizName": "毛泽东思想和中国特色社会主义理论体系概论",
            "shortName": "课",
            "key": null,
            "id": "bbe7deb100614f43a6166b1c43cce5e0",
            "time": "15:50-18:15"
        },
        {
            "bizKey": "SKKC",
            "place": "主楼主南203",
            "bizName": "计算机硬件基础（软件专业）",
            "shortName": "课",
            "key": null,
            "id": "cbc20f27b5b94c33a5ab65d507b7864f",
            "time": "14:00-15:35"
        }
    ],
    "code": "0",
    "msg": null
}