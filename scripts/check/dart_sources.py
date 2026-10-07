"""读取自有 Dart 指令闭包；支持的语法完整消费，未知指令形式明确失败。"""
from pathlib import Path
import re

REPOSITORY = Path(__file__).resolve().parents[2]
WORD = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")


class Tokens:
    def __init__(self, source):
        self.source, self.position = source, 0

    def next(self):
        source = self.source
        while self.position < len(source):
            offset = self.position
            if source[offset].isspace() or source[offset] == '\ufeff':
                self.position += 1
            elif offset == 0 and source.startswith('#!', offset):
                end = source.find('\n', offset)
                self.position = len(source) if end < 0 else end + 1
            elif source.startswith('//', offset):
                end = source.find('\n', offset)
                self.position = len(source) if end < 0 else end + 1
            elif source.startswith('/*', offset):
                self.position += 2
                depth = 1
                while depth and self.position < len(source):
                    if source.startswith('/*', self.position):
                        depth += 1
                        self.position += 2
                    elif source.startswith('*/', self.position):
                        depth -= 1
                        self.position += 2
                    else:
                        self.position += 1
                if depth:
                    raise ValueError('Dart 指令注释未闭合')
            else:
                break
        if self.position == len(source):
            return ('end', '')
        offset = self.position
        raw = source[offset:offset + 1] in {'r', 'R'} and source[offset + 1:offset + 2] in {"'", '"'}
        quote_offset = offset + int(raw)
        if source[quote_offset] in {"'", '"'}:
            quote = source[quote_offset]
            if source.startswith(quote * 3, quote_offset):
                raise ValueError('不支持的 Dart 指令三引号字符串')
            end = source.find(quote, quote_offset + 1)
            if end < 0:
                raise ValueError('Dart 指令字符串未闭合')
            value = source[quote_offset + 1:end]
            if '\n' in value or '\r' in value or (not raw and ('\\' in value or '$' in value)):
                raise ValueError('不支持的 Dart 指令转义或插值；请使用普通 URI')
            self.position = end + 1
            return ('string', value)
        match = WORD.match(source, offset)
        if match:
            self.position = match.end()
            return ('word', match.group())
        if source.startswith('==', offset):
            self.position += 2
            return ('symbol', '==')
        self.position += 1
        return ('symbol', source[offset])


def directives(source):
    """只读声明前的指令段；不把注释、方法或字符串正文当依赖。"""
    tokens, result = Tokens(source), []
    while True:
        token = tokens.next()
        if token == ('symbol', '@'):
            if tokens.next()[0] != 'word':
                raise ValueError('Dart 注解名称无效')
            while True:
                before = tokens.position
                next_token = tokens.next()
                if next_token == ('symbol', '.'):
                    if tokens.next()[0] != 'word':
                        raise ValueError('Dart 注解名称无效')
                else:
                    break
            if next_token == ('symbol', '('):
                depth = 1
                while depth:
                    next_token = tokens.next()
                    if next_token == ('end', ''):
                        raise ValueError('Dart 注解参数未闭合')
                    if next_token == ('symbol', '('):
                        depth += 1
                    elif next_token == ('symbol', ')'):
                        depth -= 1
            else:
                tokens.position = before
            continue
        if token == ('word', 'augment'):
            raise ValueError('不支持的 Dart augment 指令；不能忽略依赖')
        if token == ('symbol', '#'):
            raise ValueError('不支持的 Dart 脚本前缀；shebang 只能位于文件首行')
        if token not in [('word', name) for name in ('import', 'export', 'part', 'library')]:
            return result
        kind = token[1]
        body = []
        while True:
            token = tokens.next()
            if token == ('end', ''):
                raise ValueError('Dart 指令缺少分号')
            if token == ('symbol', ';'):
                break
            body.append(token)
        if kind == 'library':
            if any(t[0] != 'word' and t != ('symbol', '.') for t in body):
                raise ValueError('不支持的 library 指令')
            continue
        if kind == 'part' and body[:1] == [('word', 'of')]:
            kind, body = 'part of', body[1:]
        if not body or body[0][0] != 'string':
            raise ValueError('Dart 指令需要 URI；不支持具名 part of')
        result.append((kind, body.pop(0)[1]))
        if kind.startswith('part'):
            if body:
                raise ValueError('不支持的 part 指令尾部')
            continue
        while body and body[0] == ('word', 'if'):
            body.pop(0)
            if not body or body.pop(0) != ('symbol', '('):
                raise ValueError('条件导入缺少左括号')
            if not body or body.pop(0)[0] != 'word':
                raise ValueError('条件导入缺少变量')
            while body and body[0] == ('symbol', '.'):
                body.pop(0)
                if not body or body.pop(0)[0] != 'word':
                    raise ValueError('条件导入变量无效')
            if body and body[0] == ('symbol', '=='):
                body.pop(0)
                if not body or body.pop(0)[0] != 'string':
                    raise ValueError('条件导入比较值无效')
            if not body or body.pop(0) != ('symbol', ')') or not body or body[0][0] != 'string':
                raise ValueError('条件导入缺少右括号或 URI')
            result.append((kind, body.pop(0)[1]))
        if body and body[0] == ('word', 'deferred'):
            if kind != 'import':
                raise ValueError('export 不能 deferred')
            body.pop(0)
            if body[:1] != [('word', 'as')]:
                raise ValueError('deferred import 缺少 as')
        if body and body[0] == ('word', 'as'):
            if kind != 'import':
                raise ValueError('export 不能使用 as')
            body.pop(0)
            if not body or body.pop(0)[0] != 'word':
                raise ValueError('import 缺少别名')
        while body:
            if body.pop(0) not in [('word', 'show'), ('word', 'hide')]:
                raise ValueError('不支持的 Dart 指令尾部')
            if not body or body.pop(0)[0] != 'word':
                raise ValueError('show/hide 缺少名称')
            while body and body[0] == ('symbol', ','):
                body.pop(0)
                if not body or body.pop(0)[0] != 'word':
                    raise ValueError('show/hide 名称无效')


def workspace_for(root):
    root = root.resolve()
    if root.is_relative_to(REPOSITORY):
        return REPOSITORY
    return root.parent if root.name == 'integration_test' else root


class SourceClosure:
    def __init__(self, workspace, packages=None):
        self.workspace = workspace.resolve()
        self.packages = dict(packages or {})
        for parent in ('packages', 'apps'):
            for manifest in (self.workspace / parent).glob('*/pubspec.yaml'):
                match = re.search(r'^name:\s*([a-zA-Z0-9_]+)\s*$', manifest.read_text(), re.M)
                if not match:
                    raise ValueError(f'无法解析自有包名称：{manifest}')
                self.packages[match.group(1)] = manifest.parent / 'lib'
        self.sources, self.directives = {}, {}

    def excluded(self, path):
        relative = path.relative_to(self.workspace).as_posix()
        return relative.startswith(('packages/ubaa_bindings/lib/src/rust/',
                                    'packages/ubaa_bindings/cargokit/'))

    def resolve(self, parent, uri):
        if any(character in uri for character in ('%', '?', '#', '\\')):
            raise ValueError('不支持的 Dart URI 编码、查询、片段或反斜线；请使用规范源码路径')
        if uri.startswith('dart:'):
            return None
        if uri.startswith('package:'):
            package, separator, relative = uri[8:].partition('/')
            if not separator or not relative:
                raise ValueError(f'package URI 无效：{uri}')
            if package not in self.packages:
                if package.startswith('ubaa_'):
                    raise ValueError(f'未登记的自有 package：{package}')
                return None  # 外部发布包不属于自有源码政策。
            target = self.packages[package] / relative
        elif ':' in uri:
            raise ValueError(f'不支持的 Dart URI：{uri}')
        else:
            target = parent.parent / uri
        target = target.resolve()
        if not target.is_relative_to(self.workspace):
            raise ValueError(f'Dart 导入越出工作区：{uri}')
        if target.suffix != '.dart' or target.relative_to(self.workspace).parts[0] in {'examples', '.worktrees', 'ubaa_old'}:
            raise ValueError('Dart 导入指向受保护或非源码位置')
        if not target.is_file():
            raise ValueError(f'Dart 导入不存在：{uri}')
        if self.excluded(target):
            return None
        return target

    def add(self, path):
        path = path.resolve()
        if path in self.sources or self.excluded(path):
            return
        if not path.is_file():
            raise ValueError(f'Dart 源码不存在：{path}')
        self.sources[path] = path.read_text()
        try:
            self.directives[path] = directives(self.sources[path])
        except ValueError as error:
            raise ValueError(f'{path.relative_to(self.workspace)}：{error}') from error
        for kind, uri in self.directives[path]:
            target = self.resolve(path, uri)
            if target is not None:
                self.add(target)
