import { HomeCardWeekCell, HomeCardWeekRow } from '../HomeCardStore';

interface CardAction {
  action: string;
  bundleName: string;
  abilityName: string;
}

let storage = new LocalStorage();

const weekdays: Array<string> = ['一', '二', '三', '四', '五', '六', '日'];

@Entry(storage)
@Component
struct HomeCardTimetable {
  @LocalStorageProp('statusLine') statusLine: string = '';
  @LocalStorageProp('weekLabel') weekLabel: string = '';
  @LocalStorageProp('todayWeekday') todayWeekday: number = 1;
  @LocalStorageProp('weekRows') weekRows: Array<HomeCardWeekRow> = [];

  private openApp(): void {
    const action: CardAction = {
      action: 'router',
      bundleName: 'cn.edu.ubaa',
      abilityName: 'EntryAbility',
    };
    postCardAction(this, action);
  }

  private courseColor(index: number): string {
    if (index === 1) return '#E7F4EA';
    if (index === 2) return '#F2ECFF';
    if (index === 3) return '#FFF0E5';
    if (index === 4) return '#E6F5F4';
    if (index === 5) return '#FDECEF';
    if (index === 6) return '#FFF7DA';
    if (index === 7) return '#EEF1F6';
    return '#E9F0FE';
  }

  private isToday(weekday: number): boolean {
    return weekday === this.todayWeekday;
  }

  @Builder
  cell(course: HomeCardWeekCell, weekday: number) {
    Column() {
      if (!(course.title.length === 0)) {
        Text(course.title)
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1B1B1F')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (course.time.length > 0) {
          Text(`至 ${course.time}`)
            .fontSize(7)
            .fontColor('#5B6070')
            .maxLines(1)
            .margin({ top: 1 })
        }
        if (course.location.length > 0) {
          Text(course.location)
            .fontSize(7)
            .fontColor('#7A7F8C')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .layoutWeight(1)
    .height(48)
    .padding({ left: 2, right: 2, top: 2, bottom: 2 })
    .margin({ left: 1, right: 1 })
    .borderRadius(5)
    .backgroundColor(this.isToday(weekday) ? '#F4F8FF' : '#FFFFFF')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .onClick(() => this.openApp())
  }

  build() {
    Column() {
      Row() {
        Text('课程表')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1B1B1F')
        Blank()
        if (this.weekLabel.length > 0) {
          Text(this.weekLabel)
            .fontSize(9)
            .fontColor('#174CB6')
            .backgroundColor('#EAF1FF')
            .borderRadius(8)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.weekRows.length === 0) {
        Column() {
          Text(this.statusLine.length > 0 ? this.statusLine : '本周没有课程')
            .fontSize(12)
            .fontColor('#8A8A93')
          Text('打开 UBAA 查看完整课程表')
            .fontSize(9)
            .fontColor('#B0B0B8')
            .margin({ top: 5 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 14 })
        .layoutWeight(1)
        .onClick(() => this.openApp())
      } else {
        Row() {
          Text('')
            .width(42)
          ForEach(weekdays, (label: string, index: number) => {
            Text(label)
              .fontSize(9)
              .fontWeight(this.isToday(index + 1) ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.isToday(index + 1) ? '#0A59F7' : '#7A7F8C')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
          })
        }
        .width('100%')
        .margin({ top: 6, bottom: 2 })

        List() {
          ForEach(this.weekRows, (row: HomeCardWeekRow) => {
            ListItem() {
              Row() {
                Text(row.time)
                  .fontSize(8)
                  .fontColor('#8A8A93')
                  .width(42)
                  .textAlign(TextAlign.Start)
                ForEach(row.cells, (course: HomeCardWeekCell, index: number) => {
                  if (course.title.length > 0) {
                    this.cell(course, index + 1)
                  } else {
                    Column()
                      .layoutWeight(1)
                      .height(48)
                      .margin({ left: 1, right: 1 })
                      .borderRadius(5)
                      .backgroundColor(this.isToday(index + 1) ? '#F4F8FF' : '#00000000')
                      .onClick(() => this.openApp())
                  }
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }
          }, (row: HomeCardWeekRow) => row.time)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.openApp())
  }
}
